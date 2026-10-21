import Foundation
import Testing
@testable import photo_swiper

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
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), defaults: defaults)
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
}
