import Foundation
import Testing
@testable import photo_swiper

/// Counts sessions built, and can build an empty one to stand for an exhausted library.
private final class CountingBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var built: [Int] = []
    var isExhausted = false
    var estimate: ClutterEstimate?

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        built.append(number)
        return isExhausted ? Session(number: number, cards: []) : MockFeedBuilder().makeSessionNow(number: number, options: options)
    }

    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? { estimate }
}

/// Only swipes are gated: each card decision spends one free swipe, and at zero the swipe is refused
/// and the wall opens. Sessions, deleting, the pile, and undo are never gated, and unlocked nothing counts.
@MainActor
struct SessionGatingTests {
    private let library = FakeLibrary()
    private let builder = CountingBuilder()
    private let store = InMemoryProgressStore()
    private let entitlements = TestEntitlements(isUnlocked: false)
    private let clock = TestClock()
    private let center = FakeNotificationCenter()
    private let reminderDefaults = freshDefaults()
    private let allowanceDefaults = freshDefaults()
    /// The test clock reads 8 AM here, so reminders stay clear of quiet hours wherever tests run.
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Launches with `swipesLeft` free swipes, or whatever was saved (full at first) when nil.
    private func launch(swipesLeft: Int? = nil, remindersOptedIn: Bool = false) async -> FeedViewModel {
        let allowanceStore = SwipeAllowanceStore(defaults: allowanceDefaults)
        if let swipesLeft { allowanceStore.save(SwipeAllowance(balance: swipesLeft, now: clock.now)) }
        let notifier = RefillNotifier(center: center, defaults: reminderDefaults, calendar: utc)
        notifier.isOptedIn = remindersOptedIn
        let vm = FeedViewModel(
            library: library, builder: builder, store: store, entitlements: entitlements,
            allowanceStore: allowanceStore, notifier: notifier, now: { [clock] in clock.now }
        )
        await vm.start()
        return vm
    }

    /// Lets the task that schedules reminders run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func isSimilar(_ card: FeedCard?) -> Bool {
        if case .similar = card { true } else { false }
    }

    private func isBatch(_ card: FeedCard?) -> Bool {
        if case .batch = card { true } else { false }
    }

    // MARK: Sessions

    @Test func lockedFirstSessionLoads() async {
        let vm = await launch()
        #expect(vm.phase == .feed)
        #expect(vm.session?.number == 1)
        #expect(vm.swipesLeft == 20)
    }

    @Test func keepGoingAlwaysDealsTheNextSession() async {
        let vm = await launch()
        while vm.phase == .feed { vm.decide(.left) }
        #expect(vm.phase == .endOfSession)
        await vm.requestNextSession()
        #expect(vm.phase == .feed)
        #expect(vm.session?.number == 2)
    }

    @Test func relaunchingDealsANewSessionWhenLocked() async {
        let vm = await launch()
        for _ in 0..<3 { vm.decide(.left) }
        vm.finishForNow()
        store.saveSession(nil)

        let relaunched = await launch()
        #expect(relaunched.phase == .feed)
        #expect(builder.built == [1, 2])
        #expect(relaunched.swipesLeft == 17, "The allowance outlives the launch")
    }

    @Test func anExhaustedFeedIsCaughtUpNotResting() async {
        let vm = await launch()
        builder.isExhausted = true
        await vm.requestNextSession()
        #expect(vm.phase == .caughtUp)
    }

    // MARK: Spending

    @Test func everyCardCostsOneSwipeWhateverItHolds() async {
        let vm = await launch()
        var expected = 20
        while vm.phase == .feed {
            vm.decide(.left)
            expected -= 1
            #expect(vm.swipesLeft == expected)
        }
        #expect(vm.photosReviewed > 20, "Batches and similar sets hold several photos but cost one swipe")
    }

    @Test func aOneByOneReviewCostsOneSwipe() async {
        let vm = await launch()
        while vm.phase == .feed, !isBatch(vm.currentCard) { vm.decide(.right) }
        guard case .batch(let batch) = vm.currentCard else {
            Issue.record("The mock session has a batch")
            return
        }
        let before = vm.swipesLeft ?? 0
        vm.decideIndividually([batch.items[0].id: .delete])
        #expect(vm.swipesLeft == before - 1)
    }

    @Test func undoGivesTheSwipeBack() async {
        let vm = await launch(swipesLeft: 1)
        vm.decide(.left)
        #expect(vm.swipesLeft == 0)
        vm.undo()
        #expect(vm.swipesLeft == 1)
        #expect(vm.canSwipe)
    }

    @Test func undoNeverRefundsPastTheCap() async {
        let vm = await launch()
        vm.decide(.right)
        clock.advance(hours: 7)
        vm.refreshAllowance()
        #expect(vm.swipesLeft == 20)
        vm.undo()
        #expect(vm.swipesLeft == 20)
    }

    @Test func unlockedNothingIsCountedOrBlocked() async {
        entitlements.isUnlocked = true
        let vm = await launch(swipesLeft: 0)
        #expect(vm.swipesLeft == nil)
        #expect(vm.canSwipe)
        vm.decide(.left)
        #expect(vm.index == 1)
        #expect(!vm.isWallPresented)
        #expect(SwipeAllowanceStore(defaults: allowanceDefaults).load()?.remaining == 0, "Nothing was spent")
    }

    // MARK: The wall

    @Test func outOfSwipesRefusesAndOpensTheWall() async {
        let vm = await launch(swipesLeft: 0)
        let card = vm.currentCard
        vm.decide(.left)
        #expect(vm.index == 0)
        #expect(vm.currentCard == card)
        #expect(vm.pendingItems.isEmpty, "Nothing was committed")
        #expect(vm.isWallPresented)
        #expect(vm.phase == .feed, "The feed never ends; the deck stays behind the sheet")
    }

    @Test func aRefusedOneByOneReviewIsKeptAsADraft() async {
        // The mock session's batch is the ninth card, so this runs out right on it.
        let vm = await launch(swipesLeft: 8)
        while vm.phase == .feed, !isBatch(vm.currentCard) { vm.decide(.right) }
        guard case .batch(let batch) = vm.currentCard else {
            Issue.record("The mock session has a batch")
            return
        }
        #expect(vm.swipesLeft == 0)
        vm.decideIndividually([batch.items[0].id: .delete])
        #expect(vm.isWallPresented)
        #expect(vm.currentCard?.id == batch.id)
        #expect(vm.draft(for: batch)[batch.items[0].id] == .delete)
    }

    @Test func notNowClosesAndTheNextSwipeOpensItAgain() async {
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        vm.dismissWall()
        #expect(!vm.isWallPresented)
        vm.decide(.right)
        #expect(vm.isWallPresented)
    }

    @Test func theWallShowsWhatsLeft() async {
        builder.estimate = ClutterEstimate(likelyClearCount: 600, likelyClearBytes: 3_000_000_000, screenshotCount: 40, similarGroupCount: 5)
        let vm = await launch(swipesLeft: 0)
        vm.presentWall()
        await settle()
        // The two similar cards still ahead in this session count too.
        #expect(vm.clutterEstimate?.similarGroupCount == 7)
        #expect(vm.daysToFinish == 15)
        #expect(vm.nextRefillAt == clock.now.addingTimeInterval(6 * 3600))
    }

    @Test func unlockingFromTheWallLetsTheCardThrough() async {
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        #expect(await vm.unlockFromWall())
        #expect(!vm.isWallPresented)
        #expect(vm.paywallStatus == .idle)
        vm.decide(.left)
        #expect(vm.index == 1)
    }

    @Test func aFailedPurchaseStaysOnTheWall() async {
        entitlements.unlockResult = false
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        #expect(await vm.unlockFromWall() == false)
        #expect(vm.isWallPresented)
        #expect(vm.paywallStatus == .purchaseFailed)
        #expect(!vm.canSwipe)
    }

    @Test func aFailedRestoreSaysSoAndStays() async {
        entitlements.restoreResult = false
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        #expect(await vm.restoreFromWall() == false)
        #expect(vm.isWallPresented)
        #expect(vm.paywallStatus == .restoreFailed)
    }

    @Test func aSuccessfulRestoreLetsTheCardThrough() async {
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        #expect(await vm.restoreFromWall())
        vm.decide(.left)
        #expect(vm.index == 1)
    }

    @Test func deletingTheMarkedPileWorksAtZero() async {
        let vm = await launch(swipesLeft: 3)
        for _ in 0..<3 { vm.decide(.left) }
        vm.decide(.left)
        #expect(vm.isWallPresented)
        #expect(vm.pendingItems.count == 3)
        #expect(await vm.confirmDelete())
        #expect(vm.freedBytes > 0)
        #expect(!vm.isWallPresented)
    }

    @Test func deletingFromThePileWorksAtZero() async {
        let vm = await launch(swipesLeft: 2)
        for _ in 0..<2 { vm.decide(.left) }
        #expect(await vm.deleteNow(Array(vm.pendingItems.prefix(1))))
        #expect(vm.pendingItems.count == 1)
    }

    // MARK: Refills

    @Test func aRefillLandingLetsSwipesThrough() async {
        let vm = await launch(swipesLeft: 0)
        clock.advance(hours: 6)
        vm.decide(.right)
        #expect(vm.index == 1)
        #expect(vm.swipesLeft == 9)
    }

    @Test func aRefillPutsTheStrongestCardsFirst() async {
        let vm = await launch(swipesLeft: 0)
        #expect(!isSimilar(vm.currentCard))
        clock.advance(hours: 6)
        vm.refreshAllowance()
        #expect(isSimilar(vm.currentCard))
        if case .video = vm.nextCard {} else { Issue.record("A big video separates the similar sets") }
    }

    @Test func aRefillWhileRestingFrontLoadsTheNextSession() async {
        let vm = await launch(swipesLeft: 1)
        vm.decide(.left)
        vm.finishForNow()
        clock.advance(hours: 6)
        vm.refreshAllowance()
        await vm.requestNextSession()
        #expect(isSimilar(vm.currentCard))
    }

    // MARK: Reminders

    @Test func hittingZeroSchedulesRemindersWhenOptedIn() async {
        let vm = await launch(swipesLeft: 1, remindersOptedIn: true)
        vm.decide(.left)
        await settle()
        #expect(Set(center.pending.keys) == Set(RefillReminder.allIDs))
    }

    @Test func hittingZeroSchedulesNothingWithoutOptingIn() async {
        let vm = await launch(swipesLeft: 1)
        vm.decide(.left)
        await settle()
        #expect(center.added.isEmpty)
    }

    @Test func remindMeAtZeroAsksThenSchedules() async {
        let vm = await launch(swipesLeft: 0)
        vm.decide(.left)
        await vm.remindWhenSwipesAreBack()
        #expect(vm.isRemindersOptedIn)
        #expect(center.authorizationRequests == 1)
        #expect(center.pending[RefillReminder.nextID] != nil)
    }

    @Test func swipingAgainCancelsPendingReminders() async {
        let vm = await launch(swipesLeft: 1, remindersOptedIn: true)
        vm.decide(.left)
        await settle()
        clock.advance(hours: 6)
        vm.decide(.left)
        #expect(center.pending.isEmpty)
    }

    @Test func unlockingCancelsPendingReminders() async {
        let vm = await launch(swipesLeft: 1, remindersOptedIn: true)
        vm.decide(.left)
        await settle()
        vm.decide(.left)
        #expect(await vm.unlockFromWall())
        #expect(center.pending.isEmpty)
    }
}
