import Foundation

/// The words on the paywall, kept together because they sit next to a price: what the unlock includes and
/// how each plan is billed should only change on purpose. Pure, so the tests can pin them.
enum UnlockCopy {
    struct Benefit: Equatable {
        let systemImage: String
        let title: String
        let detail: String
    }

    static let headline = "Clear without limits."

    static let supporting = "Everything in the free version, with no waiting and no cap on your pile."

    /// What the unlock adds. These are claims about the purchase, and each is true in code: free swipes
    /// are metered and refill (`SwipeGate.canSwipe`), and the free pile is capped (`SwipeGate.pileLimitBytes`).
    /// Don't add one without checking it the same way: grouped cards, for one, are free too.
    static let benefits: [Benefit] = [
        Benefit(systemImage: "infinity", title: "Unlimited swipes", detail: "No waiting for more to arrive."),
        Benefit(systemImage: "trash", title: "No pile limit", detail: "Clear as much as you like in one go."),
    ]

    /// A plan card's name.
    static func title(for plan: UnlockPlan.Kind) -> String {
        switch plan {
        case .once: "Once"
        case .monthly: "Monthly"
        }
    }

    /// What follows the price on a plan card, if anything.
    static func priceSuffix(for plan: UnlockPlan.Kind) -> String? {
        switch plan {
        case .once: nil
        case .monthly: "/ month"
        }
    }

    /// A plan card's one line on how it's paid.
    static func detail(for plan: UnlockPlan.Kind) -> String {
        switch plan {
        case .once: "Pay one time. Yours for good."
        case .monthly: "Renews each month. Cancel anytime."
        }
    }

    /// The buy button, which names the plan and its price.
    static func buttonTitle(for plan: UnlockPlan) -> String {
        switch plan.kind {
        case .once: "Unlock for \(plan.displayPrice)"
        case .monthly: "Subscribe for \(plan.displayPrice) / month"
        }
    }

    /// The buy button as VoiceOver reads it: the price and how it's billed, in one go.
    static func buttonAccessibilityLabel(for plan: UnlockPlan) -> String {
        switch plan.kind {
        case .once: "Unlock for \(plan.displayPrice), one-time purchase"
        case .monthly: "Subscribe for \(plan.displayPrice) a month, renews monthly until cancelled"
        }
    }

    /// How the chosen plan is billed, said once, under the buy button.
    static func billingNote(for plan: UnlockPlan) -> String {
        switch plan.kind {
        case .once: "One-time purchase. No renewals."
        case .monthly: "\(plan.displayPrice) a month until you cancel."
        }
    }

    /// The line under the buttons after a purchase or restore that didn't unlock. Nil while idle,
    /// working, or once it worked (the screen closes itself then).
    static func message(for status: PaywallStatus) -> String? {
        switch status {
        case .purchaseFailed: "The purchase didn't go through. You weren't charged."
        case .purchasePending: "Waiting for approval. You'll be unlocked as soon as it's approved."
        case .nothingToRestore: "We couldn't find an earlier purchase to restore."
        case .restoreFailed: "Couldn't reach the App Store. Try again in a moment."
        case .idle, .purchasing, .restoring, .restored: nil
        }
    }
}
