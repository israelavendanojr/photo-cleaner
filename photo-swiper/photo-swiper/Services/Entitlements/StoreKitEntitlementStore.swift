import Foundation
import Observation
import os
import StoreKit

/// What the App Store sells. Either one unlocks everything.
enum StoreProducts {
    /// The lifetime unlock, a non-consumable.
    static let unlock = "com.israelavendanojr.photo-swiper.unlock"
    /// The same unlock as an auto-renewing monthly subscription.
    static let monthly = "com.israelavendanojr.photo-swiper.monthly"

    static let all = [unlock, monthly]

    static func id(for plan: UnlockPlan.Kind) -> String {
        switch plan {
        case .once: unlock
        case .monthly: monthly
        }
    }

    static func plan(for productID: String) -> UnlockPlan.Kind? {
        switch productID {
        case unlock: .once
        case monthly: .monthly
        default: nil
        }
    }
}

/// The unlock, bought and restored through StoreKit 2: the lifetime product, or the monthly subscription
/// while it runs.
///
/// `isUnlocked` starts from the last known state so the app doesn't flash locked at launch, then
/// `Transaction.currentEntitlements` corrects it, before anything that needs the network. Only verified,
/// unrevoked transactions count. Whether a subscription is still running is StoreKit's call, not a date
/// compared here: it keeps a subscriber entitled through a billing grace period, when the transaction's
/// own end date has already passed.
/// `Transaction.updates` is watched for as long as the store lives (the life of the app), which
/// covers purchases on other devices, Ask to Buy approvals, renewals and refunds. A subscription's end
/// isn't always announced, so the store also asks again when the current period runs out.
@Observable
@MainActor
final class StoreKitEntitlementStore: EntitlementStore {
    private static let log = Logger.app(category: "entitlement")
    /// How soon to ask again about a subscription that's past its end date but still entitled: in a
    /// billing grace period, or renewed with the new transaction not here yet.
    nonisolated static let recheckInterval: TimeInterval = 600

    private(set) var isUnlocked: Bool
    private(set) var activePlan: UnlockPlan.Kind?
    private var products: [String: Product] = [:]
    /// Each plan only once its product has loaded: the price beside a buy button has to be the store's.
    /// The subscription also has to be what the paywall's words say it is, see `matchesMonthlyCopy`.
    var plans: [UnlockPlan] {
        var plans: [UnlockPlan] = []
        if let once = products[StoreProducts.unlock] {
            plans.append(UnlockPlan(kind: .once, displayPrice: once.displayPrice))
        }
        if let monthly = products[StoreProducts.monthly], Self.matchesMonthlyCopy(monthly) {
            plans.append(UnlockPlan(kind: .monthly, displayPrice: monthly.displayPrice))
        }
        return plans
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sync: () async throws -> Void
    // Unsafe: written once in init and read only in deinit, which can't be isolated before Swift 6.2.
    @ObservationIgnored private nonisolated(unsafe) var updates: Task<Void, Never>?
    @ObservationIgnored private var launch: Task<Void, Never>?
    /// Waits out the subscription's current period, then asks again.
    @ObservationIgnored private var expiryCheck: Task<Void, Never>?
    /// Counts entitlement reads, so one that started earlier can't overwrite a later one's answer.
    @ObservationIgnored private var generation = 0

    /// `sync` is `AppStore.sync()`, replaceable in tests.
    init(defaults: UserDefaults = .standard, sync: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.defaults = defaults
        self.sync = sync
        isUnlocked = defaults.bool(forKey: DefaultsKey.storeKitUnlocked)
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        launch = Task { [weak self] in
            await self?.finishUnfinished()
            // Before the products: this reads what the device already knows, and a lapsed subscriber
            // shouldn't stay unlocked for as long as a slow network takes.
            await self?.refreshEntitlements()
            await self?.loadProducts()
        }
    }

    deinit {
        updates?.cancel()
    }

    /// Waits for the launch work: the first entitlement check and the products.
    func ready() async {
        await launch?.value
    }

    func purchase(_ plan: UnlockPlan.Kind) async -> PurchaseOutcome {
        // So a slow launch check can't land after the purchase and relock.
        await ready()
        let id = StoreProducts.id(for: plan)
        if products[id] == nil { await loadProducts() }
        guard let product = products[id] else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                // The whole picture, not just this transaction: a subscriber may already own the lifetime unlock.
                await refreshEntitlements()
                // In case the entitlement list hasn't caught up with a purchase that just finished.
                if !isUnlocked, let bought = Self.unlockingPlan(transaction, now: .now) {
                    activePlan = bought
                    setUnlocked(true)
                    scheduleExpiryCheck(bought == .monthly ? transaction.expirationDate : nil)
                }
                return isUnlocked ? .purchased : .failed
            case .success(.unverified(_, let error)):
                Self.log.error("Purchase couldn't be verified: \(error.localizedDescription, privacy: .public)")
                return .failed
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    func restore() async -> RestoreOutcome {
        await ready()
        do {
            try await sync()
        } catch {
            Self.log.error("App Store sync failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        await refreshEntitlements()
        return isUnlocked ? .restored : .nothingToRestore
    }

    /// Fetches any product that's still missing, so a paywall opened after a failed launch fetch can
    /// offer its plans.
    func reloadPlans() async {
        await ready()
        guard StoreProducts.all.contains(where: { products[$0] == nil }) else { return }
        await loadProducts()
    }

    /// Re-reads what this Apple Account owns. Either product unlocks; the lifetime one outranks the
    /// subscription as the active plan, since it never lapses.
    func refreshEntitlements() async {
        generation &+= 1
        let read = generation
        var owned: Set<UnlockPlan.Kind> = []
        var subscriptionEnds: Date?
        for await result in Transaction.currentEntitlements {
            // No end-date test: StoreKit lists a subscription for exactly as long as it entitles, which
            // includes a billing grace period past the transaction's own end.
            guard case .verified(let transaction) = result,
                  let plan = Self.unlockingPlan(productID: transaction.productID, revokedAt: transaction.revocationDate,
                                                expiresAt: nil, isUpgraded: transaction.isUpgraded, now: .now)
            else { continue }
            owned.insert(plan)
            if plan == .monthly { subscriptionEnds = transaction.expirationDate }
        }
        // A read that started after this one has the newer picture; leave the answer to it.
        guard read == generation else { return }
        activePlan = Self.activePlan(among: owned)
        setUnlocked(!owned.isEmpty)
        // Only a subscription that's the reason the app is unlocked needs watching.
        scheduleExpiryCheck(activePlan == .monthly ? subscriptionEnds : nil)
    }

    /// The lifetime unlock outranks a subscription: it's the one that never lapses.
    nonisolated static func activePlan(among owned: Set<UnlockPlan.Kind>) -> UnlockPlan.Kind? {
        owned.contains(.once) ? .once : owned.contains(.monthly) ? .monthly : nil
    }

    /// When to ask again about a subscription that ends at `end`: just after that, or, if it's already
    /// past and still entitled, after `recheckInterval`.
    nonisolated static func nextCheck(end: Date, now: Date) -> Date {
        end > now ? end.addingTimeInterval(1) : now.addingTimeInterval(recheckInterval)
    }

    /// Whether the subscription is what `UnlockCopy` tells the buyer: one month a period, and no
    /// introductory offer, which the paywall would have to disclose.
    nonisolated static func matchesMonthlyCopy(_ product: Product) -> Bool {
        guard let subscription = product.subscription else { return false }
        return matchesMonthlyCopy(period: subscription.subscriptionPeriod, hasIntroductoryOffer: subscription.introductoryOffer != nil)
    }

    nonisolated static func matchesMonthlyCopy(period: Product.SubscriptionPeriod, hasIntroductoryOffer: Bool) -> Bool {
        period.unit == .month && period.value == 1 && !hasIntroductoryOffer
    }

    /// The plan a just-bought transaction unlocks, if it does: one of the app's two products, not
    /// refunded or revoked, not replaced by an upgrade, and not past its end.
    nonisolated static func unlockingPlan(_ transaction: Transaction, now: Date) -> UnlockPlan.Kind? {
        unlockingPlan(productID: transaction.productID, revokedAt: transaction.revocationDate,
                      expiresAt: transaction.expirationDate, isUpgraded: transaction.isUpgraded, now: now)
    }

    /// The rule itself, on plain values so it can be tested without a store.
    nonisolated static func unlockingPlan(
        productID: String, revokedAt: Date?, expiresAt: Date?, isUpgraded: Bool, now: Date
    ) -> UnlockPlan.Kind? {
        guard let plan = StoreProducts.plan(for: productID), revokedAt == nil, !isUpgraded else { return nil }
        if let expiresAt, expiresAt <= now { return nil }
        return plan
    }

    // MARK: Private

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refreshEntitlements()
    }

    /// Anything verified but left unfinished, e.g. the app quit mid-purchase.
    private func finishUnfinished() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    /// Tried at launch, and again on the next purchase if a product is still missing.
    private func loadProducts() async {
        do {
            for product in try await Product.products(for: StoreProducts.all) {
                products[product.id] = product
            }
            for plan in UnlockPlan.Kind.allCases where products[StoreProducts.id(for: plan)] == nil {
                Self.log.error("A product wasn't found: \(plan.rawValue, privacy: .public)")
            }
            if let monthly = products[StoreProducts.monthly], !Self.matchesMonthlyCopy(monthly) {
                Self.log.error("The subscription isn't one month with no offer, so it isn't listed")
            }
        } catch {
            Self.log.error("Couldn't load the products: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A lapsed subscription relocks when its period ends, even if StoreKit sends nothing then. A renewal
    /// arrives as a new transaction with a later end, which schedules the next check.
    private func scheduleExpiryCheck(_ end: Date?) {
        expiryCheck?.cancel()
        expiryCheck = nil
        guard let end else { return }
        let wait = Self.nextCheck(end: end, now: .now).timeIntervalSinceNow
        expiryCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, wait)))
            guard !Task.isCancelled, let self else { return }
            // Let go first, so the read this starts can't be cancelled halfway by its own rescheduling.
            expiryCheck = nil
            await refreshEntitlements()
        }
    }

    private func setUnlocked(_ unlocked: Bool) {
        if isUnlocked != unlocked { isUnlocked = unlocked }
        defaults.set(unlocked, forKey: DefaultsKey.storeKitUnlocked)
    }
}
