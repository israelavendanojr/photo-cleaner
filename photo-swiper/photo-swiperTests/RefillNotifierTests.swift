import Foundation
import Testing
@testable import photo_swiper

/// Refill reminders: quiet hours, the daily cap, copy, and cancelling.
@MainActor
struct RefillNotifierTests {
    private let t = SwipeAllowance.Tunables.standard
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    private let center = FakeNotificationCenter()
    private let defaults = freshDefaults()

    private func at(day: Int = 10, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    private func notifier(optedIn: Bool = true) -> RefillNotifier {
        let notifier = RefillNotifier(center: center, defaults: defaults, calendar: calendar)
        notifier.isOptedIn = optedIn
        return notifier
    }

    // MARK: Planner

    @Test func daytimeTimesAreLeftAlone() {
        #expect(RefillReminderPlanner.outsideQuietHours(at(14, 30), calendar: calendar) == at(14, 30))
        #expect(RefillReminderPlanner.outsideQuietHours(at(9), calendar: calendar) == at(9))
    }

    @Test func lateEveningMovesToNineTheNextMorning() {
        #expect(RefillReminderPlanner.outsideQuietHours(at(22, 30), calendar: calendar) == at(day: 11, 9))
        #expect(RefillReminderPlanner.outsideQuietHours(at(21), calendar: calendar) == at(day: 11, 9))
    }

    @Test func earlyMorningMovesToNineTheSameDay() {
        #expect(RefillReminderPlanner.outsideQuietHours(at(3, 15), calendar: calendar) == at(9))
    }

    @Test func plansTheRefillAndTheFullReminder() {
        let plan = RefillReminderPlanner.plan(
            nextRefillAt: at(12), fullAt: at(18), tunables: t, estimate: nil, log: [], calendar: calendar
        )
        #expect(plan.map(\.id) == [RefillReminder.nextID, RefillReminder.fullID])
        #expect(plan.map(\.fireAt) == [at(12), at(18)])
        #expect(plan[1].body == "Your 20 swipes are ready")
    }

    @Test func bothLandingAtNineKeepsOnlyTheFullOne() {
        let plan = RefillReminderPlanner.plan(
            nextRefillAt: at(23), fullAt: at(day: 11, 5), tunables: t, estimate: nil, log: [], calendar: calendar
        )
        #expect(plan.map(\.id) == [RefillReminder.fullID])
        #expect(plan.first?.fireAt == at(day: 11, 9))
    }

    @Test func noDayGetsMoreThanTwo() {
        let plan = RefillReminderPlanner.plan(
            nextRefillAt: at(15), fullAt: at(day: 11, 10), tunables: t, estimate: nil,
            log: [at(10), at(13)], calendar: calendar
        )
        #expect(plan.map(\.id) == [RefillReminder.fullID])
    }

    @Test func theCopyUsesRealNumbersAndFallsBack() {
        let groups = ClutterEstimate(likelyClearBytes: 2_000_000_000, similarGroupCount: 3)
        #expect(RefillReminderPlanner.refillBody(amount: 10, estimate: groups) == "10 swipes are back · 3 sets of similar shots waiting")
        let one = ClutterEstimate(similarGroupCount: 1)
        #expect(RefillReminderPlanner.refillBody(amount: 10, estimate: one) == "10 swipes are back · 1 set of similar shots waiting")
        let bytes = ClutterEstimate(likelyClearBytes: 1_200_000_000)
        #expect(RefillReminderPlanner.refillBody(amount: 10, estimate: bytes) == "10 swipes are back · about 1.20 GB to clear")
        #expect(RefillReminderPlanner.refillBody(amount: 10, estimate: nil) == "10 swipes are back")
        #expect(RefillReminderPlanner.refillBody(amount: 10, estimate: ClutterEstimate()) == "10 swipes are back")
    }

    // MARK: Notifier

    @Test func nothingIsScheduledWithoutOptingIn() async {
        await notifier(optedIn: false).scheduleOnEmpty(nextRefillAt: at(12), fullAt: at(18), tunables: t, estimate: nil, now: at(6))
        #expect(center.added.isEmpty)
    }

    @Test func optingInAsksOnceAndRemembers() async {
        let notifier = notifier(optedIn: false)
        #expect(await notifier.optIn())
        #expect(center.authorizationRequests == 1)
        #expect(RefillNotifier(center: center, defaults: defaults).isOptedIn)
    }

    @Test func aRefusedPermissionIsNotAnOptIn() async {
        center.grants = false
        let notifier = notifier(optedIn: false)
        #expect(await notifier.optIn() == false)
        #expect(!notifier.isOptedIn)
    }

    @Test func schedulingAgainReplacesInsteadOfDuplicating() async {
        let notifier = notifier()
        await notifier.scheduleOnEmpty(nextRefillAt: at(12), fullAt: at(18), tunables: t, estimate: nil, now: at(6))
        await notifier.scheduleOnEmpty(nextRefillAt: at(12), fullAt: at(18), tunables: t, estimate: nil, now: at(6))
        #expect(center.pending.count == 2)
    }

    @Test func theDailyCapCountsEarlierReminders() async {
        let notifier = notifier()
        await notifier.scheduleOnEmpty(nextRefillAt: at(11), fullAt: at(17), tunables: t, estimate: nil, now: at(5))
        #expect(center.pending.count == 2)

        // Back after the first fired, and out again: the cancelled 5 PM one no longer counts,
        // but the 11 AM one that fired does.
        notifier.cancelAll(now: at(12))
        await notifier.scheduleOnEmpty(nextRefillAt: at(18), fullAt: at(20), tunables: t, estimate: nil, now: at(12, 30))
        #expect(center.pending.keys.sorted() == [RefillReminder.nextID])
        #expect(center.pending[RefillReminder.nextID]?.fireAt == at(18))
    }

    @Test func cancellingRemovesEverythingPending() async {
        let notifier = notifier()
        await notifier.scheduleOnEmpty(nextRefillAt: at(12), fullAt: at(18), tunables: t, estimate: nil, now: at(6))
        notifier.cancelAll(now: at(7))
        #expect(center.pending.isEmpty)
    }
}
