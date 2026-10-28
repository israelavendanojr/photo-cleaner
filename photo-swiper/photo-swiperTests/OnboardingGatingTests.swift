import Foundation
import Testing
@testable import photo_swiper

/// Records the options each session is built with, and can hold a build until `release()`.
private final class GatedBuilder: FeedBuilding, @unchecked Sendable {
    var isGated = false
    private(set) var requests: [FeedOptions] = []
    private var waiting: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { waiting != nil }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        requests.append(options)
        if isGated { await withCheckedContinuation { waiting = $0 } }
        return MockFeedBuilder().makeSessionNow(number: number, options: options)
    }

    func release() {
        isGated = false
        waiting?.resume()
        waiting = nil
    }
}

/// Onboarding shows only before the user has been asked for photo access, and the system
/// prompt waits for the Allow tap.
@MainActor
struct OnboardingGatingTests {
    private let library = FakeLibrary()
    private let defaults: UserDefaults

    init() {
        let suite = "OnboardingGatingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func launched(
        entitlements: TestEntitlements? = nil,
        center: FakeNotificationCenter? = nil
    ) async -> FeedViewModel {
        let entitlements = entitlements ?? TestEntitlements()
        let notifier = center.map { RefillNotifier(center: $0, defaults: defaults) }
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: entitlements,
                               defaults: defaults, notifier: notifier)
        await vm.start()
        return vm
    }

    /// Advances past every step after photo access, the way tapping on through them would.
    private func finishOnboarding(_ vm: FeedViewModel) async {
        for _ in 0..<3 where vm.phase == .onboarding { await vm.advanceOnboarding() }
    }

    @Test func aFreshInstallStopsAtOnboardingWithoutPrompting() async {
        library.needsPrompt = true
        let vm = await launched()
        #expect(vm.phase == .onboarding)
        #expect(library.requestCount == 0)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded) == false)
    }

    @Test func alreadyAuthorizedSkipsStraightToTheFeed() async {
        library.needsPrompt = false
        let vm = await launched()
        #expect(vm.phase == .feed)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded) == false)
    }

    @Test func aDebugResetShowsOnboardingAgainOnceAfterAccessWasGranted() async {
        library.needsPrompt = false
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        let first = await launched()
        #expect(first.phase == .feed)

        first.debugResetOnboarding()
        let relaunched = await launched()
        #expect(relaunched.phase == .onboarding)
        await relaunched.start()
        await finishOnboarding(relaunched)
        #expect(relaunched.phase == .feed)

        let again = await launched()
        #expect(again.phase == .feed)
    }

    @Test func onboardedButUnansweredAsksDirectly() async {
        library.needsPrompt = true
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        let vm = await launched()
        #expect(vm.phase == .feed)
        #expect(library.requestCount == 1)
    }

    @Test func deniedAfterAllowShowsNoAccess() async {
        library.needsPrompt = true
        library.access = .denied
        let vm = await launched()
        await vm.start()
        #expect(vm.phase == .noAccess)
        #expect(library.requestCount == 1)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded))
    }

    @Test func limitedAfterAllowOpensTheFeed() async {
        library.needsPrompt = true
        library.access = .limited
        let vm = await launched()
        await vm.start()
        #expect(vm.phase == .onboarding, "The steps after access still show")
        await finishOnboarding(vm)
        #expect(vm.phase == .feed)
        #expect(vm.access == .limited)
        #expect(vm.session != nil)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded))
    }

    @Test func allowKeepsOnboardingUpWhileTheFirstSessionBuilds() async {
        library.needsPrompt = true
        let builder = GatedBuilder()
        builder.isGated = true
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        let allow = Task { await vm.start() }
        while !builder.isWaiting { await Task.yield() }
        #expect(vm.phase == .onboarding)
        #expect(vm.isPreparingFirstSession)

        builder.release()
        await allow.value
        #expect(vm.phase == .onboarding, "Held until onboarding's last step")
        #expect(vm.session != nil)
        #expect(!vm.isPreparingFirstSession)

        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
    }

    @Test func theFirstPageSkipsPlaceNamesAndLaterOnesDont() async {
        library.needsPrompt = true
        let builder = GatedBuilder()
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        await vm.start()
        await finishOnboarding(vm)
        while vm.cards.count - vm.index > FeedViewModel.pageAhead { vm.decide(.right) }
        await vm.waitForPage()
        #expect(builder.requests.map(\.placeBudget) == [.zero, FeedOptions().placeBudget])
    }

    @Test func retryingFromNoAccessShowsLoadingNotOnboarding() async {
        library.needsPrompt = true
        library.access = .denied
        let builder = GatedBuilder()
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        await vm.start()
        #expect(vm.phase == .noAccess)

        library.access = .full
        builder.isGated = true
        let retry = Task { await vm.start() }
        while !builder.isWaiting { await Task.yield() }
        #expect(vm.phase == .loading)
        #expect(!vm.isPreparingFirstSession)
        builder.release()
        await retry.value
        #expect(vm.phase == .feed)
        #expect(builder.requests.map(\.placeBudget) == [FeedOptions().placeBudget])
    }

    // MARK: Steps after photo access

    @Test func grantedGoesThroughRemindersAndTheOfferToTheFeed() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: FakeNotificationCenter())
        #expect(vm.onboardingPageCount == 4)
        await vm.start()
        #expect(vm.phase == .onboarding)
        #expect(vm.isOnboardingAccessGranted)
        #expect(vm.session != nil, "The first deck is built underneath")
        #expect(!vm.canUndo)

        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)
        #expect(vm.onboardingPageIndex == 2)
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
        #expect(vm.onboardingPageIndex == 3)
        #expect(vm.phase == .onboarding)

        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded))
    }

    @Test func limitedAccessGetsTheSameSteps() async {
        library.needsPrompt = true
        library.access = .limited
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: FakeNotificationCenter())
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
        #expect(vm.access == .limited)
    }

    @Test func remindersAlreadyDecidedSkipStraightToTheOffer() async {
        library.needsPrompt = true
        let center = FakeNotificationCenter()
        center.undetermined = false
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: center)
        #expect(vm.onboardingPageCount == 3)
        await vm.start()

        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
        #expect(vm.onboardingPageIndex == 2)
        #expect(center.authorizationRequests == 0)
    }

    @Test func noNotifierSkipsTheRemindersStep() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false))
        await vm.start()

        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
    }

    @Test func alreadyUnlockedSkipsTheOffer() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: true), center: FakeNotificationCenter())
        #expect(vm.onboardingPageCount == 3)
        await vm.start()

        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)
        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
    }

    @Test func nothingLeftToOfferFinishesStraightAfterAccess() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: true))
        await vm.start()

        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
    }

    @Test func aRestoreDuringRemindersSkipsTheOffer() async {
        library.needsPrompt = true
        let entitlements = TestEntitlements(isUnlocked: false)
        let vm = await launched(entitlements: entitlements, center: FakeNotificationCenter())
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)

        entitlements.isUnlocked = true
        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
    }

    @Test func buyingFromTheOfferOpensTheFeed() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false))
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)

        #expect(await vm.purchaseUnlock())
        // The offer moves on by itself once unlocked.
        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
        #expect(vm.isUnlocked)
    }

    @Test func turningOnRemindersDuringOnboardingShowsOnTheWall() async {
        library.needsPrompt = true
        let center = FakeNotificationCenter()
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: center)
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)

        await vm.remindWhenSwipesAreBack()
        await vm.advanceOnboarding()

        #expect(center.authorizationRequests == 1)
        #expect(vm.isRemindersOptedIn, "The wall says reminders are on instead of offering them")
        #expect(!vm.areRemindersDenied)
    }

    @Test func refusingRemindersDuringOnboardingStillMovesOn() async {
        library.needsPrompt = true
        let center = FakeNotificationCenter()
        center.grants = false
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: center)
        await vm.start()
        await vm.advanceOnboarding()

        await vm.remindWhenSwipesAreBack()
        await vm.advanceOnboarding()

        #expect(vm.onboardingStep == .upsell)
        #expect(vm.areRemindersDenied)
    }

    @Test func finishingBeforeTheDeckIsReadyWaitsForIt() async {
        library.needsPrompt = true
        let builder = GatedBuilder()
        builder.isGated = true
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        let allow = Task { await vm.start() }
        while !builder.isWaiting { await Task.yield() }

        await vm.advanceOnboarding()
        #expect(vm.phase == .onboarding)
        #expect(vm.isLeavingOnboarding)

        builder.release()
        await allow.value
        #expect(vm.phase == .feed)
        #expect(!vm.isLeavingOnboarding)
    }

    @Test func anOnboardingKilledAfterAccessReopensOnTheFeed() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: FakeNotificationCenter())
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)

        library.needsPrompt = false
        let relaunched = await launched(entitlements: TestEntitlements(isUnlocked: false), center: FakeNotificationCenter())
        #expect(relaunched.phase == .feed)
    }

    @Test func aDebugReplayShowsEveryStepEvenWhenDecided() async {
        library.needsPrompt = false
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        let center = FakeNotificationCenter()
        center.undetermined = false
        let first = await launched(center: center)
        #expect(first.phase == .feed)

        first.debugResetOnboarding()
        let replay = await launched(entitlements: TestEntitlements(isUnlocked: true), center: center)
        #expect(replay.phase == .onboarding)
        #expect(replay.onboardingPageCount == 4)
        await replay.start()
        await replay.advanceOnboarding()
        #expect(replay.onboardingStep == .notifications)
        await replay.advanceOnboarding()
        #expect(replay.onboardingStep == .upsell)
        await replay.advanceOnboarding()
        #expect(replay.phase == .feed)

        let again = await launched(center: center)
        #expect(again.phase == .feed)
    }

    // MARK: Going back

    @Test func goingBackRetracesTheStepsAndForwardReachesThemAgain() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: FakeNotificationCenter())
        await vm.start()
        #expect(!vm.canGoBackInOnboarding, "The primer and Welcome go back in the view")
        await vm.advanceOnboarding()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)

        vm.goBackInOnboarding()
        #expect(vm.onboardingStep == .notifications)
        vm.goBackInOnboarding()
        #expect(vm.onboardingStep == .intro)
        #expect(vm.phase == .onboarding, "The feed stays held while the user looks back")
        #expect(vm.onboardingPageCount == 4)

        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications)
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
        await vm.advanceOnboarding()
        #expect(vm.phase == .feed)
        #expect(defaults.bool(forKey: DefaultsKey.hasOnboarded))
    }

    @Test func withoutRemindersTheOfferGoesBackToThePrimer() async {
        library.needsPrompt = true
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false))
        await vm.start()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)

        vm.goBackInOnboarding()
        #expect(vm.onboardingStep == .intro)
    }

    @Test func answeredRemindersStillShowWhenComingBackThrough() async {
        library.needsPrompt = true
        let center = FakeNotificationCenter()
        let vm = await launched(entitlements: TestEntitlements(isUnlocked: false), center: center)
        await vm.start()
        await vm.advanceOnboarding()
        await vm.remindWhenSwipesAreBack()
        await vm.advanceOnboarding()
        #expect(!center.undetermined, "iOS has answered, so the step wouldn't be offered fresh")

        vm.goBackInOnboarding()
        vm.goBackInOnboarding()
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .notifications, "The page dots don't change on the way back through")
        #expect(vm.isRemindersOptedIn)
        #expect(center.authorizationRequests == 1)
    }

    @Test func noGoingBackOnceFinished() async {
        library.needsPrompt = true
        let builder = GatedBuilder()
        builder.isGated = true
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(isUnlocked: false),
                               defaults: defaults)
        await vm.start()
        let allow = Task { await vm.start() }
        while !builder.isWaiting { await Task.yield() }
        await vm.advanceOnboarding()
        #expect(vm.onboardingStep == .upsell)
        #expect(vm.canGoBackInOnboarding)

        await vm.advanceOnboarding()
        #expect(vm.isLeavingOnboarding)
        #expect(!vm.canGoBackInOnboarding)
        vm.goBackInOnboarding()
        #expect(vm.onboardingStep == .upsell)

        builder.release()
        await allow.value
        #expect(vm.phase == .feed)
    }
}
