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

    private func launched() async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        return vm
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
        #expect(vm.phase == .feed)
        #expect(!vm.isPreparingFirstSession)
    }

    @Test func theFirstSessionSkipsPlaceNamesAndLaterOnesDont() async {
        library.needsPrompt = true
        let builder = GatedBuilder()
        let vm = FeedViewModel(library: library, builder: builder, entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        await vm.start()
        await vm.requestNextSession()
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
}
