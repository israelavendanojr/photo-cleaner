import Foundation
import Testing
@testable import photo_swiper

/// The words on the unlock screens (JUN-44). They sit next to a price, so changes should be deliberate.
@MainActor
struct UpsellCopyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Countdown headline

    @Test func refillLineCountsDownToTheNextRefill() {
        let next = now.addingTimeInterval(2 * 3600 + 14 * 60)
        let line = UnlockCopy.refillLine(canSwipe: false, nextRefillAt: next, refillAmount: 10, now: now)
        #expect(line == "+10 in \(Format.countdown(next.timeIntervalSince(now)))")
        #expect(line.hasPrefix("+10 in "), "The wall's UI test looks for this prefix")
    }

    @Test(arguments: [nil, -5.0, 0.0])
    func refillLineSaysAnyMomentOnceDue(offset: Double?) {
        let next = offset.map { now.addingTimeInterval($0) }
        #expect(UnlockCopy.refillLine(canSwipe: false, nextRefillAt: next, refillAmount: 10, now: now) == "+10 any moment now")
    }

    @Test func refillLineSaysSwipesAreBackWhenTheyAre() {
        let next = now.addingTimeInterval(3600)
        #expect(UnlockCopy.refillLine(canSwipe: true, nextRefillAt: next, refillAmount: 10, now: now) == "Swipes are back")
    }

    // MARK: Supporting lines

    @Test func wallSupportingLineUsesThePaceWhenItIsSlow() {
        let line = UnlockCopy.wallSupporting(daysToFinish: 28)
        #expect(line == "At this pace, \(Format.roughDays(28)). Unlock to finish today.")
    }

    @Test(arguments: [nil, 0.5, 1.9])
    func wallSupportingLineFallsBackWithoutAPace(days: Double?) {
        #expect(UnlockCopy.wallSupporting(daysToFinish: days) == "Unlock to keep swiping without waiting.")
    }

    @Test func settingsSheetHasItsOwnSupportingLine() {
        #expect(UnlockCopy.sheetSupporting == "Everything in the free version, without the limits.")
    }

    // MARK: What's included

    @Test func includedKeepsTheThreeExistingClaims() {
        #expect(UnlockCopy.included.map(\.text) == [
            "Unlimited swipes",
            "Similar-shot picks and screenshot batches",
            "Future updates included",
        ])
        #expect(UnlockCopy.included.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test func priceNoteStillSaysOneTimeWithNoSubscription() {
        #expect(UnlockCopy.priceNote == "One-time purchase. No subscription, no trial, no renewals.")
    }

    // MARK: Status messages

    @Test(arguments: [PaywallStatus.idle, .purchasing, .restoring, .restored])
    func quietStatusesShowNoMessage(status: PaywallStatus) {
        #expect(UnlockCopy.message(for: status) == nil)
    }

    @Test func failuresAndWaitsExplainThemselves() {
        #expect(UnlockCopy.message(for: .purchaseFailed) == "The purchase didn't go through. You weren't charged.")
        #expect(UnlockCopy.message(for: .purchasePending) == "Waiting for approval. You'll be unlocked as soon as it's approved.")
        #expect(UnlockCopy.message(for: .nothingToRestore) == "We couldn't find an earlier purchase to restore.")
        #expect(UnlockCopy.message(for: .restoreFailed) == "Couldn't reach the App Store. Try again in a moment.")
    }
}
