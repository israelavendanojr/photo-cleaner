import Foundation
import Observation

/// What lets a swipe through: the free allowance, the wall and the unlock purchase, and the free
/// pile limit. `FeedViewModel` owns it and adds what reaches beyond it: front-loading the deck on a
/// refill, reminders, and the follow-ups a wall affects.
@Observable
@MainActor
final class SwipeGate {
    typealias PaywallStatus = FeedViewModel.PaywallStatus

    /// What an item of unknown size (zero bytes) counts as toward the free pile limit: a typical photo.
    static let unknownSizeBytes: Int64 = 3_000_000

    var paywallStatus = PaywallStatus.idle // internal set for FeedViewModel+Mock
    /// The free swipes. Never spent or checked while unlocked.
    var allowance: SwipeAllowance // internal set for FeedViewModel+Mock
    /// "Out of swipes": the wall sheet over the feed, offering the unlock.
    var isWallPresented = false
    /// Bought or restored since launch. The review prompt never follows a purchase.
    private(set) var purchasedThisLaunch = false
    /// Off while mocks play swipes through, so their setup doesn't spend the allowance.
    var chargesSwipes = true // internal set for FeedViewModel+Mock

    private let entitlements: any EntitlementStore
    private let allowanceStore: SwipeAllowanceStore
    /// Where the free tier's limits come from: the swipe allowance and the pile limit.
    private let freeTier: FreeTierTunables
    private let now: () -> Date

    init(entitlements: any EntitlementStore, allowanceStore: SwipeAllowanceStore, freeTier: FreeTierTunables, now: @escaping () -> Date) {
        self.entitlements = entitlements
        self.allowanceStore = allowanceStore
        self.freeTier = freeTier
        self.now = now
        allowance = allowanceStore.load() ?? SwipeAllowance(tunables: freeTier.limits.allowance, now: now())
    }

    var allowanceTunables: SwipeAllowance.Tunables { freeTier.limits.allowance }

    private var isUnlocked: Bool { entitlements.isUnlocked }

    /// A card decision would go through. Unlocked, always.
    var canSwipe: Bool { isUnlocked || allowance.remaining > 0 }
    /// A card decision gets past the allowance: swipes left, or none being charged.
    var admitsSwipe: Bool { canSwipe || !chargesSwipes }
    /// Free swipes left; nil when unlocked, where nothing is counted.
    var swipesLeft: Int? { isUnlocked ? nil : allowance.remaining }
    /// When the next refill lands; nil when unlocked or full.
    var nextRefillAt: Date? { isUnlocked ? nil : allowance.nextRefillAt(allowanceTunables) }

    // MARK: Pile limit

    /// How much a free user's pile holds, e.g. 1 GB, unlocked or not.
    var freeBinBytes: Int64 { freeTier.limits.freeBinBytes }
    /// The most the pile holds before deleting, in bytes; nil when unlocked, where it has no limit.
    var pileLimitBytes: Int64? { isUnlocked ? nil : freeBinBytes }
    /// The pile has a limit to check: a free user, with swipes being charged.
    var isPileLimited: Bool { pileLimitBytes != nil && chargesSwipes }

    /// A free user's pile is at its limit, so only keeps and laters go through.
    func isPileFull(counted: @autoclosure () -> Int64) -> Bool {
        pileLimitBytes.map { counted() >= $0 } ?? false
    }

    /// The pile can take `added` on top of `pending`. An empty pile takes anything, even one item
    /// (or group) bigger than the whole limit.
    func pileTakes(_ added: [LibraryItem], onto pending: [LibraryItem]) -> Bool {
        guard let limit = pileLimitBytes, chargesSwipes else { return true }
        guard !added.isEmpty, !pending.isEmpty else { return true }
        return Self.countedBytes(pending) + Self.countedBytes(added) <= limit
    }

    /// Sizes toward the pile limit. An unknown (zero) size counts as `unknownSizeBytes`, so a pile of
    /// them still fills up.
    static func countedBytes(_ items: [LibraryItem]) -> Int64 {
        items.reduce(0) { $0 + ($1.bytes > 0 ? $1.bytes : unknownSizeBytes) }
    }

    // MARK: Allowance

    /// Credits any refills owed by now. True when a refill landed.
    func creditRefills() -> Bool {
        guard !isUnlocked else { return false }
        var settled = allowance
        let refilled = settled.settle(at: now(), allowanceTunables)
        guard settled != allowance else { return false }
        allowance = settled
        allowanceStore.save(settled)
        return refilled
    }

    /// Spends one swipe for a card decision. Unlocked, nothing is counted. True if one was spent.
    func spend() -> Bool {
        guard chargesSwipes, !isUnlocked, allowance.spend(at: now(), allowanceTunables) else { return false }
        allowanceStore.save(allowance)
        return true
    }

    /// Gives back a swipe an undone decision spent.
    func refund() {
        allowance.refund(at: now(), allowanceTunables)
        allowanceStore.save(allowance)
    }

    /// Fits the saved allowance to new swipe tunables. False if they didn't change.
    func fitAllowance(from before: SwipeAllowance.Tunables) -> Bool {
        let after = allowanceTunables
        guard after != before else { return false }
        allowance.adjust(from: before, to: after, at: now())
        allowanceStore.save(allowance)
        return true
    }

    /// Replaces the free swipes left. Nil fills them to the cap.
    func debugSetSwipes(_ balance: Int?) {
        allowance = balance.map { SwipeAllowance(balance: $0, tunables: allowanceTunables, now: now()) }
            ?? SwipeAllowance(tunables: allowanceTunables, now: now())
        allowanceStore.save(allowance)
    }

    // MARK: Wall and purchase

    /// Opens the wall: the countdown, what's left, and the unlock. The deck stays underneath.
    func openWall() {
        if !isWallPresented { paywallStatus = .idle }
        isWallPresented = true
    }

    /// "Not now". The next refused swipe opens it again.
    func dismissWall() {
        guard !isPurchaseBusy else { return }
        isWallPresented = false
    }

    /// A purchase or restore is running. The wall and the Settings unlock can't close meanwhile.
    var isPurchaseBusy: Bool { paywallStatus == .purchasing || paywallStatus == .restoring }

    /// Buys the unlock, from the wall or Settings. Closes the wall, so the current card can be swiped
    /// straight away. False if it didn't go through; a cancel says nothing.
    func purchaseUnlock() async -> Bool {
        guard !isPurchaseBusy else { return false }
        paywallStatus = .purchasing
        switch await entitlements.unlock() {
        case .purchased where entitlements.isUnlocked:
            didUnlock()
            paywallStatus = .idle
            return true
        case .cancelled:
            paywallStatus = .idle
        case .pending:
            paywallStatus = .purchasePending
        case .purchased, .failed:
            paywallStatus = .purchaseFailed
        }
        return false
    }

    /// The unlock changed outside a purchase run here: Ask to Buy approved, bought on another
    /// device, or refunded. Unlocking closes the wall; relocking needs nothing, gating reads it live.
    /// True when it unlocked.
    func entitlementChanged() -> Bool {
        guard isUnlocked, !isPurchaseBusy else { return false }
        if paywallStatus == .purchasePending {
            purchasedThisLaunch = true
            paywallStatus = .idle
        }
        isWallPresented = false
        return true
    }

    /// Restores an earlier purchase, from the wall or Settings. True if the app is now unlocked;
    /// `paywallStatus` says what was found either way.
    func restorePurchases() async -> Bool {
        guard !isPurchaseBusy else { return false }
        paywallStatus = .restoring
        switch await entitlements.restore() {
        case .restored where entitlements.isUnlocked:
            didUnlock()
            paywallStatus = .restored
            return true
        case .nothingToRestore:
            paywallStatus = .nothingToRestore
        case .restored, .failed:
            paywallStatus = .restoreFailed
        }
        return false
    }

    /// Clears a finished purchase or restore message, e.g. when Settings opens. Not while one runs.
    func resetPurchaseStatus() {
        guard !isPurchaseBusy else { return }
        paywallStatus = .idle
    }

    /// Bought or restored: the wall, if up, closes.
    private func didUnlock() {
        purchasedThisLaunch = true
        isWallPresented = false
    }
}
