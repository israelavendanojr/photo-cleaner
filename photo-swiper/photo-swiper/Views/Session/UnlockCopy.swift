import Foundation

/// The words on the unlock screens (the swipe wall, the post-delete sheet and Settings' sheet), kept
/// together because they sit next to a price: what the purchase includes and how it's billed should
/// only change on purpose. Pure, so the tests can pin them.
enum UnlockCopy {
    struct Item: Equatable {
        let systemImage: String
        let text: String
    }

    /// What the unlock adds. These are claims about the purchase; don't add one without sign-off.
    static let included: [Item] = [
        Item(systemImage: "infinity", text: "Unlimited swipes"),
        Item(systemImage: "square.stack.3d.up", text: "Similar-shot picks and screenshot batches"),
        Item(systemImage: "arrow.down.circle", text: "Future updates included"),
    ]

    static let includedTitle = "Unlocking adds"

    /// How it's billed, said once, under the buy button.
    static let priceNote = "One-time purchase. No subscription, no trial, no renewals."

    /// Settings' sheet, which has no moment of its own to explain.
    static let sheetSupporting = "Everything in the free version, without the limits."

    /// The wall's headline: "+10 in 2h 14m". Once the refill is due, or has landed while the wall is
    /// up, says so plainly.
    static func refillLine(canSwipe: Bool, nextRefillAt: Date?, refillAmount: Int, now: Date) -> String {
        if canSwipe { return "Swipes are back" }
        guard let next = nextRefillAt, next.timeIntervalSince(now) > 0 else { return "+\(refillAmount) any moment now" }
        return "+\(refillAmount) in \(Format.countdown(next.timeIntervalSince(now)))"
    }

    /// The wall's supporting line. The pace only when it's slow enough to be worth saying.
    static func wallSupporting(daysToFinish: Double?) -> String {
        if let days = daysToFinish, days >= 2 {
            return "At this pace, \(Format.roughDays(days)). Unlock to finish today."
        }
        return "Unlock to keep swiping without waiting."
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
