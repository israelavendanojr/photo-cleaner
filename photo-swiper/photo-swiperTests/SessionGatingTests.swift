import Foundation
import Testing
@testable import photo_swiper

/// Counts sessions built, and can build an empty one to stand for an exhausted library.
private final class CountingBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var built: [Int] = []
    var isExhausted = false

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        built.append(number)
        return isExhausted ? Session(number: number, cards: []) : MockFeedBuilder().makeSessionNow(number: number, options: options)
    }
}

/// The first session is free; any later one asks for the unlock first. Deleting, the pile,
/// and undo are never gated.
@MainActor
struct SessionGatingTests {
    private let library = FakeLibrary()
    private let builder = CountingBuilder()
    private let store = InMemoryProgressStore()
    private let entitlements = TestEntitlements(isUnlocked: false)

    private func launch() async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: builder, store: store, entitlements: entitlements)
        await vm.start()
        return vm
    }

    /// Launches and finishes the first session with a few deletes left pending.
    private func finishedFirstSession() async -> FeedViewModel {
        let vm = await launch()
        for _ in 0..<3 { vm.decide(.left) }
        vm.finishForNow()
        return vm
    }

    @Test func lockedFirstSessionLoads() async {
        let vm = await launch()
        #expect(vm.phase == .feed)
        #expect(vm.session?.number == 1)
    }

    @Test func lockedSecondSessionOpensThePaywall() async {
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(vm.phase == .paywall)
        #expect(vm.session?.number == 1)
        #expect(builder.built == [1])
    }

    @Test func keepGoingFromTheEndScreenOpensThePaywall() async {
        let vm = await launch()
        while vm.phase == .feed { vm.decide(.left) }
        #expect(vm.phase == .endOfSession)
        await vm.requestNextSession()
        #expect(vm.phase == .paywall)
        #expect(builder.built == [1])
    }

    @Test func relaunchingIntoANewLockedSessionOpensThePaywall() async {
        _ = await finishedFirstSession()
        store.saveSession(nil)

        let relaunched = await launch()
        #expect(relaunched.phase == .paywall)
        #expect(builder.built == [1])
    }

    @Test func aSessionInProgressResumesEvenWhenLocked() async {
        entitlements.isUnlocked = true
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        vm.decide(.right)
        entitlements.isUnlocked = false

        let relaunched = await launch()
        #expect(relaunched.phase == .feed)
        #expect(relaunched.session?.number == 2)
    }

    @Test func unlockedLoadsTheNextSession() async {
        entitlements.isUnlocked = true
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(vm.phase == .feed)
        #expect(vm.session?.number == 2)
    }

    @Test func notNowRestsAndStaysRestingOnRelaunch() async {
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        vm.dismissPaywall()
        #expect(vm.phase == .resting)
        #expect(!vm.isWelcomeBack)

        let relaunched = await launch()
        #expect(relaunched.phase == .resting)
        #expect(relaunched.isWelcomeBack)
    }

    @Test func unlockingFromThePaywallLoadsTheSecondSession() async {
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(await vm.unlockFromPaywall())
        #expect(vm.isUnlocked)
        #expect(vm.phase == .feed)
        #expect(vm.session?.number == 2)
        #expect(vm.paywallStatus == .idle)
    }

    @Test func aFailedPurchaseStaysOnThePaywall() async {
        entitlements.unlockResult = false
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(await vm.unlockFromPaywall() == false)
        #expect(vm.phase == .paywall)
        #expect(vm.paywallStatus == .purchaseFailed)
        #expect(builder.built == [1])
    }

    @Test func aFailedRestoreSaysSoAndStays() async {
        entitlements.restoreResult = false
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(await vm.restoreFromPaywall() == false)
        #expect(vm.phase == .paywall)
        #expect(vm.paywallStatus == .restoreFailed)
    }

    @Test func aSuccessfulRestoreLoadsTheSecondSession() async {
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(await vm.restoreFromPaywall())
        #expect(vm.session?.number == 2)
    }

    @Test func deletingStillWorksOnThePaywall() async {
        let vm = await finishedFirstSession()
        await vm.requestNextSession()
        #expect(vm.pendingItems.count == 3)
        #expect(await vm.deleteNow(Array(vm.pendingItems.prefix(1))))
        #expect(vm.pendingItems.count == 2)
        #expect(vm.freedBytes > 0)
        #expect(vm.phase == .paywall)
    }

    @Test func deletingStillWorksWhileResting() async {
        let vm = await finishedFirstSession()
        #expect(vm.phase == .resting)
        #expect(await vm.deleteNow(vm.pendingItems))
        #expect(vm.pendingItems.isEmpty)
    }

    @Test func undoWithinTheFirstSessionIsNotGated() async {
        let vm = await launch()
        while vm.phase == .feed { vm.decide(.left) }
        vm.undo()
        #expect(vm.phase == .feed)
    }

    @Test func anExhaustedFeedIsCaughtUpNotResting() async {
        entitlements.isUnlocked = true
        let vm = await finishedFirstSession()
        builder.isExhausted = true
        await vm.requestNextSession()
        #expect(vm.phase == .caughtUp)
    }
}
