import Foundation
import Testing
@testable import photo_swiper

/// Admin Tools' test notifications: the real body text, a test id a few seconds out, a banner in the
/// foreground, a tap that routes like the real one, and the real reminders left alone.
@MainActor
struct AdminNotificationTests {
    private let clock = TestClock()
    private let center = FakeNotificationCenter()
    private let defaults = freshDefaults()
    private let tunables = SwipeAllowance.Tunables(cap: 30, refillAmount: 12)

    private func make(notifier: RefillNotifier? = nil) -> (FeedViewModel, RefillNotifier) {
        let notifier = notifier ?? RefillNotifier(center: center, defaults: defaults)
        let clock = clock
        let vm = FeedViewModel(
            library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false),
            defaults: defaults, allowanceTunables: tunables, notifier: notifier, now: { clock.now }
        )
        return (vm, notifier)
    }

    @Test func theRefillNotificationQuotesTheCurrentEstimate() async throws {
        let (vm, _) = make()

        let raised = try #require(await vm.admin.raiseNotification(.refill))

        let estimate = try #require(vm.clutterEstimate, "Worked out before raising")
        #expect(raised.body == RefillReminderPlanner.refillBody(amount: 12, estimate: estimate))
        #expect(raised.body.hasPrefix("12 swipes are back · "))
        #expect(center.added == [raised])
    }

    @Test func theFullNotificationHasTheRealBody() async throws {
        let (vm, _) = make()

        let raised = try #require(await vm.admin.raiseNotification(.full))

        #expect(raised.body == "Your 30 swipes are ready")
        #expect(raised.body == RefillReminderPlanner.fullBody(cap: 30))
    }

    @Test(arguments: AdminNotification.allCases)
    func itFiresAFewSecondsLaterWithATestID(_ kind: AdminNotification) async throws {
        let (vm, _) = make()

        let raised = try #require(await vm.admin.raiseNotification(kind))

        #expect(RefillReminder.isTest(raised.id))
        #expect(!RefillReminder.allIDs.contains(raised.id))
        #expect(raised.fireAt == clock.now.addingTimeInterval(AdminController.notificationDelay))
    }

    @Test func raisingLeavesTheRealRemindersAlone() async throws {
        let notifier = RefillNotifier(center: center, defaults: defaults)
        #expect(await notifier.optIn())
        await notifier.scheduleOnEmpty(
            nextRefillAt: clock.now.addingTimeInterval(3600), fullAt: clock.now.addingTimeInterval(7200),
            tunables: tunables, estimate: nil, now: clock.now
        )
        let realPending = center.pending
        let log = defaults.array(forKey: DefaultsKey.refillReminderLog) as? [Date]
        let (vm, _) = make(notifier: notifier)

        await vm.admin.raiseNotification(.refill)
        await vm.admin.raiseNotification(.full)

        #expect(notifier.isOptedIn)
        #expect(defaults.array(forKey: DefaultsKey.refillReminderLog) as? [Date] == log, "Not counted toward the daily cap")
        for (id, reminder) in realPending { #expect(center.pending[id] == reminder, "\(id) still scheduled as it was") }
        #expect(center.pending.count == realPending.count + 2)
    }

    @Test func raisingDoesNotOptInOrSchedule() async throws {
        let (vm, notifier) = make()

        await vm.admin.raiseNotification(.refill)

        #expect(!notifier.isOptedIn)
        #expect(!vm.isRemindersOptedIn)
        #expect(defaults.array(forKey: DefaultsKey.refillReminderLog) == nil)
        #expect(center.pending.keys.allSatisfy { RefillReminder.isTest($0) })
    }

    @Test func onlyTestIDsGoThroughTheTestHook() async {
        let notifier = RefillNotifier(center: center, defaults: defaults)

        await notifier.raiseTest(RefillReminder(id: RefillReminder.nextID, fireAt: clock.now, body: "x"))

        #expect(center.added.isEmpty)
    }

    // MARK: Permission

    @Test func permissionReadsNotAskedThenGranted() async {
        let (vm, notifier) = make()
        #expect(await vm.admin.notificationPermission() == .notAsked)

        #expect(await vm.admin.requestNotificationPermission() == .granted)
        #expect(center.authorizationRequests == 1)
        #expect(!notifier.isOptedIn, "Asking from Admin Tools doesn't opt in to reminders")
    }

    @Test func permissionReadsDenied() async {
        center.undetermined = false
        center.denied = true
        let (vm, _) = make()

        #expect(await vm.admin.notificationPermission() == .denied)
    }

    @Test func withoutANotifierNothingCanBeRaised() async {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(), defaults: defaults)

        #expect(!vm.admin.canRaiseNotifications)
        #expect(await vm.admin.raiseNotification(.refill) == nil)
    }

    // MARK: AppDelegate

    @Test(arguments: AdminNotification.allCases)
    func testNotificationsShowABannerInTheForeground(_ kind: AdminNotification) {
        #expect(AppDelegate.foregroundOptions(for: kind.testID).contains(.banner))
    }

    @Test(arguments: RefillReminder.allIDs)
    func realRemindersStaySilentInTheForeground(_ id: String) {
        #expect(AppDelegate.foregroundOptions(for: id).isEmpty)
    }

    @Test func tapsOnRealAndTestRemindersOpenTheFeed() {
        for id in RefillReminder.allIDs + AdminNotification.allCases.map(\.testID) {
            #expect(RefillReminder.routesToFeed(id), "\(id)")
        }
        #expect(!RefillReminder.routesToFeed("something.else"))
    }
}
