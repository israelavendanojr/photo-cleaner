import Foundation
import Observation

/// Whether the unlock is owned, and the ways to buy or restore it.
///
/// `StoreKitEntitlementStore` runs the real thing; mocks use `DebugEntitlementStore`. Views never ask
/// this directly; `FeedViewModel` decides what's gated.
@MainActor
protocol EntitlementStore: AnyObject, Observable {
    var isUnlocked: Bool { get }
    /// Localized price of the one-time unlock, e.g. "$9.99".
    var displayPrice: String { get }
    /// What's on sale right now, in the order the paywall shows it. A plan whose product hasn't loaded
    /// isn't listed, so nothing is offered that can't be bought.
    var plans: [UnlockPlan] { get }
    /// Runs the purchase of one plan.
    func purchase(_ plan: UnlockPlan.Kind) async -> PurchaseOutcome
    /// Looks for an earlier purchase.
    func restore() async -> RestoreOutcome
}

extension EntitlementStore {
    /// Buys the one-time unlock.
    func unlock() async -> PurchaseOutcome { await purchase(.once) }
}

/// How a purchase ended.
enum PurchaseOutcome: Equatable, Sendable {
    /// Bought; the app is now unlocked.
    case purchased
    /// The user backed out. Nothing to say.
    case cancelled
    /// Waiting on someone else, e.g. Ask to Buy. Unlocks later if approved.
    case pending
    /// It didn't go through, e.g. offline or the payment was declined.
    case failed
}

/// What a restore found.
enum RestoreOutcome: Equatable, Sendable {
    /// An earlier purchase was found; the app is now unlocked.
    case restored
    /// The App Store answered, and this Apple Account never bought the unlock.
    case nothingToRestore
    /// The App Store couldn't be asked, e.g. offline.
    case failed
}
