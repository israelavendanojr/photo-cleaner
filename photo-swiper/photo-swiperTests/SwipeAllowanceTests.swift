import Foundation
import Testing
@testable import photo_swiper

/// The free swipe allowance on its own: spending, refills, clamps, and clocks that misbehave.
struct SwipeAllowanceTests {
    private let t = SwipeAllowance.Tunables.standard
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func hours(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }

    /// An allowance with `spent` swipes spent at `start`.
    private func spent(_ spent: Int) -> SwipeAllowance {
        var allowance = SwipeAllowance(tunables: t, now: start)
        for _ in 0..<spent { _ = allowance.spend(at: start, t) }
        return allowance
    }

    @Test func startsFullWithNoTimer() {
        let allowance = SwipeAllowance(tunables: t, now: start)
        #expect(allowance.remaining == 20)
        #expect(allowance.nextRefillAt(t) == nil)
        #expect(allowance.refillsToFull(t) == 0)
    }

    @Test func refillsNeverGoPastTheCap() {
        var allowance = spent(1)
        allowance.settle(at: hours(6), t)
        #expect(allowance.remaining == 20)
        #expect(allowance.nextRefillAt(t) == nil)
    }

    @Test func aPartialRefillIsClampedToTheCap() {
        var allowance = spent(5)
        #expect(allowance.remaining == 15)
        #expect(allowance.refillsToFull(t) == 1)
        allowance.settle(at: hours(6), t)
        #expect(allowance.remaining == 20)
    }

    @Test func nothingIsCreditedBeforeTheIntervalEnds() {
        var allowance = spent(20)
        let settleResult = allowance.settle(at: hours(5.99), t)
        #expect(settleResult == false)
        #expect(allowance.remaining == 0)
        #expect(allowance.nextRefillAt(t) == hours(6))
        #expect(allowance.fullAt(t) == hours(12))
    }

    @Test func aLongAbsenceCreditsEveryRefillOwed() {
        var allowance = spent(20)
        #expect(allowance.refillsToFull(t) == 2)
        allowance.settle(at: hours(7), t)
        #expect(allowance.remaining == 10)
        // The next timer started when the first one ended, not on return.
        #expect(allowance.nextRefillAt(t) == hours(12))
        allowance.settle(at: hours(50), t)
        #expect(allowance.remaining == 20)
    }

    @Test func manyRefillsAtOnceStillClamp() {
        var allowance = SwipeAllowance(balance: 0, tunables: SwipeAllowance.Tunables(cap: 50), now: start)
        allowance.settle(at: hours(19), SwipeAllowance.Tunables(cap: 50))
        #expect(allowance.remaining == 30)
    }

    @Test func theTimerStopsAtTheCapAndRestartsOnTheNextSpend() {
        var allowance = spent(3)
        allowance.settle(at: hours(6), t)
        #expect(allowance.nextRefillAt(t) == nil)

        let spent = allowance.spend(at: hours(9), t)
        #expect(spent)
        #expect(allowance.remaining == 19)
        #expect(allowance.nextRefillAt(t) == hours(15))
    }

    @Test func spendingAtZeroFailsAndChangesNothing() {
        var allowance = spent(20)
        let before = allowance
        let spendResult = allowance.spend(at: hours(1), t)
        #expect(spendResult == false)
        #expect(allowance.remaining == 0)
        #expect(allowance.nextRefillAt(t) == before.nextRefillAt(t))
    }

    @Test func aRefundIsClampedToTheCap() {
        var allowance = spent(1)
        allowance.refund(at: start, t)
        #expect(allowance.remaining == 20)
        #expect(allowance.nextRefillAt(t) == nil)
        allowance.refund(at: start, t)
        #expect(allowance.remaining == 20)
    }

    @Test func aRefundBelowTheCapKeepsTheTimer() {
        var allowance = spent(4)
        allowance.refund(at: hours(1), t)
        #expect(allowance.remaining == 17)
        #expect(allowance.nextRefillAt(t) == hours(6))
    }

    @Test func aClockSetBackGrantsNothing() {
        var allowance = spent(20)
        allowance.settle(at: hours(3), t)
        // Set back, then forward past where the refill would have been from the earlier time.
        let setBack = allowance.settle(at: hours(-30), t)
        #expect(setBack == false)
        #expect(allowance.remaining == 0)
        let stillBehind = allowance.settle(at: hours(2), t)
        #expect(stillBehind == false)
        #expect(allowance.remaining == 0)
        // Back to real time, the refill lands on schedule.
        let onTime = allowance.settle(at: hours(6), t)
        #expect(onTime)
        #expect(allowance.remaining == 10)
    }

    @Test func aClockSetFarBackThenSpendingDoesNotRewindTheTimer() {
        var allowance = spent(19)
        allowance.settle(at: hours(2), t)
        let spendResult = allowance.spend(at: hours(-100), t)
        #expect(spendResult)
        #expect(allowance.remaining == 0)
        allowance.settle(at: hours(6), t)
        #expect(allowance.remaining == 10)
    }

    @Test func daylightSavingDoesNotChangeTheInterval() throws {
        // New York falls back at 2 AM on November 1, 2026: an hour repeats.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
        var allowance = SwipeAllowance(balance: 0, tunables: t, now: midnight)

        let early = allowance.settle(at: midnight.addingTimeInterval(6 * 3600 - 1), t)
        #expect(early == false)
        let due = midnight.addingTimeInterval(6 * 3600)
        let onTime = allowance.settle(at: due, t)
        #expect(onTime)
        #expect(allowance.remaining == 10)
        // Six real hours read as 5 AM on the wall clock after the change.
        #expect(calendar.component(.hour, from: due) == 5)
    }

    @MainActor @Test func itSurvivesASaveAndLoad() {
        let store = SwipeAllowanceStore(defaults: freshDefaults())
        let allowance = spent(7)
        store.save(allowance)
        #expect(store.load() == allowance)
    }

    @Test func swipesPerDayFollowsTheTunables() {
        #expect(t.swipesPerDay == 40)
    }
}
