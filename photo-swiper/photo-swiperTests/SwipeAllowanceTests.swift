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

    // MARK: Changing tunables (Developer mode)

    @Test func aLowerCapTrimsTheBalanceAndStopsTheTimer() {
        var allowance = spent(5)
        allowance.adjust(from: t, to: SwipeAllowance.Tunables(cap: 10), at: start)
        #expect(allowance.remaining == 10)
        #expect(allowance.nextRefillAt(t) == nil)
    }

    @Test func aHigherCapStartsTheTimerFromFull() {
        var allowance = SwipeAllowance(tunables: t, now: start)
        let higher = SwipeAllowance.Tunables(cap: 30)
        allowance.adjust(from: t, to: higher, at: hours(1))
        #expect(allowance.remaining == 20)
        #expect(allowance.nextRefillAt(higher) == hours(7))
        allowance.settle(at: hours(7), higher)
        #expect(allowance.remaining == 30)
    }

    @Test func refillsOwedUnderTheOldTunablesAreCreditedFirst() {
        var allowance = spent(20)
        allowance.adjust(from: t, to: SwipeAllowance.Tunables(refillInterval: 60), at: hours(6))
        #expect(allowance.remaining == 10)
    }
}

/// The one place the free tier's limits come from, and Developer mode's overrides of them.
@MainActor
struct FreeTierTunablesTests {
    private func devMode(on: Bool) -> DevMode {
        let devMode = DevMode(environment: .testFlight, defaults: freshDefaults())
        devMode.setEnabled(on)
        return devMode
    }

    @Test func theDefaultsAreTheHardcodedValues() {
        let tier = FreeTierTunables(defaults: freshDefaults(), devMode: devMode(on: true))
        #expect(tier.limits == .standard)
        #expect(tier.value(.swipeCap) == 20)
        #expect(tier.value(.refillAmount) == 10)
        #expect(tier.value(.refillIntervalMinutes) == 360)
        #expect(tier.value(.freeBinMB) == 1_000)
        #expect(!tier.isCustomized)
    }

    @Test func overridesApplyLiveAndAreSaved() {
        let defaults = freshDefaults()
        let devMode = devMode(on: true)
        let tier = FreeTierTunables(defaults: defaults, devMode: devMode)

        tier.set(.swipeCap, 50)
        tier.set(.refillAmount, 5)
        tier.set(.refillIntervalMinutes, 60)
        tier.set(.freeBinMB, 250)

        #expect(tier.limits.allowance == SwipeAllowance.Tunables(cap: 50, refillAmount: 5, refillInterval: 3600))
        #expect(tier.limits.freeBinBytes == 250_000_000)
        #expect(tier.limits.allowance.swipesPerDay == 120)
        #expect(tier.defaultValue(.swipeCap) == 20, "Defaults stay beside the fields")
        let relaunched = FreeTierTunables(defaults: defaults, devMode: devMode)
        #expect(relaunched.limits == tier.limits)
    }

    @Test func valuesAreClampedToTheirRanges() {
        let tier = FreeTierTunables(defaults: freshDefaults(), devMode: devMode(on: true))
        tier.set(.swipeCap, 0)
        tier.set(.refillAmount, 9_999)
        tier.set(.refillIntervalMinutes, 2_000)
        tier.set(.freeBinMB, 1)
        #expect(tier.value(.swipeCap) == 1)
        #expect(tier.value(.refillAmount) == 500)
        #expect(tier.value(.refillIntervalMinutes) == 1_440)
        #expect(tier.value(.freeBinMB) == 10)
    }

    @Test func developerModeOffIgnoresSavedOverrides() {
        let defaults = freshDefaults()
        let devMode = devMode(on: true)
        let tier = FreeTierTunables(defaults: defaults, devMode: devMode)
        tier.set(.swipeCap, 50)

        devMode.setEnabled(false)
        #expect(tier.limits == .standard)
        #expect(defaults.integer(forKey: FreeTierTunable.swipeCap.defaultsKey) == 50, "Kept for next time")

        devMode.setEnabled(true)
        #expect(tier.value(.swipeCap) == 50)
    }

    @Test func resetGoesBackToTheDefaults() {
        let defaults = freshDefaults()
        let tier = FreeTierTunables(defaults: defaults, devMode: devMode(on: true))
        tier.set(.freeBinMB, 300)
        tier.set(.swipeCap, 7)
        #expect(tier.isCustomized)

        tier.resetToDefaults()

        #expect(tier.limits == .standard)
        #expect(!tier.isCustomized)
        #expect(defaults.object(forKey: FreeTierTunable.freeBinMB.defaultsKey) == nil)
    }

    @Test func refillSoonIsTheBaselineAndShowsAsOneMinute() {
        let tier = FreeTierTunables(baseline: FreeTierLimits(allowance: .refillSoon), defaults: freshDefaults(), devMode: devMode(on: true))
        #expect(tier.limits.allowance.refillInterval == 60)
        #expect(tier.defaultValue(.refillIntervalMinutes) == 1)
    }

    @Test func fixedTunablesNeverChange() {
        let tier = FreeTierTunables.fixed(FreeTierLimits(allowance: SwipeAllowance.Tunables(cap: 1_000)))
        tier.set(.swipeCap, 3)
        #expect(tier.limits.allowance.cap == 1_000)
    }

    @Test func theViewModelFollowsATunedCap() {
        let devMode = devMode(on: true)
        let tier = FreeTierTunables(defaults: freshDefaults(), devMode: devMode)
        let builder = MockFeedBuilder()
        let vm = FeedViewModel(
            library: FakeLibrary(), builder: builder, entitlements: TestEntitlements(isUnlocked: false),
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: 500, reviewedItems: 0, freedBytes: 0), freeTier: tier
        )
        #expect(vm.swipesLeft == 20)

        vm.setFreeTierValue(.swipeCap, 5)
        #expect(vm.swipesLeft == 5)
        #expect(vm.allowanceTunables.cap == 5)

        vm.setFreeTierValue(.swipeCap, 8)
        #expect(vm.swipesLeft == 5)
        #expect(vm.nextRefillAt != nil, "Below the new cap, the refill timer runs")

        vm.resetFreeTierToDefaults()
        #expect(vm.allowanceTunables == .standard)
    }
}
