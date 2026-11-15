import Foundation

/// One way to pay for the unlock, as the paywall offers it. Either one unlocks everything; they differ
/// only in how they're billed.
struct UnlockPlan: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// The lifetime unlock, bought once.
        case once
        /// The same unlock, renewed each month.
        case monthly
    }

    let kind: Kind
    /// The store's localized price, e.g. "$9.99". Never written by hand.
    let displayPrice: String

    var id: Kind { kind }
}
