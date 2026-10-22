import Foundation
import Observation

/// Whether the one-time unlock is owned, and the way to buy or restore it.
///
/// `DebugEntitlementStore` stands in until StoreKit lands. Views never ask this directly;
/// `FeedViewModel` decides what's gated.
@MainActor
protocol EntitlementStore: AnyObject, Observable {
    var isUnlocked: Bool { get }
    /// Localized price for the unlock button, e.g. "$12.99".
    var displayPrice: String { get }
    /// Runs the purchase. True once unlocked; false if cancelled or failed.
    func unlock() async -> Bool
    /// Looks for an earlier purchase. True if one was found and the app is now unlocked.
    func restore() async -> Bool
}
