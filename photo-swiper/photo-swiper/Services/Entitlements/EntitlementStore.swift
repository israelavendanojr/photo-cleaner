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
    /// Looks for an earlier purchase.
    func restore() async -> RestoreOutcome
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
