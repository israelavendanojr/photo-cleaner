import Foundation
import Testing
@testable import photo_swiper

/// Asking for a review after a big delete.
@MainActor
struct ReviewPromptTests {
    private let mb: Int64 = 1_000_000

    // MARK: Eligibility

    @Test func needsAHundredMegabytesFreed() {
        #expect(!ReviewPrompt.isEligible(freedBytes: 100 * mb - 1, priorDeletes: 3, lastAskedVersion: nil, currentVersion: "1.0"))
        #expect(ReviewPrompt.isEligible(freedBytes: 100 * mb, priorDeletes: 3, lastAskedVersion: nil, currentVersion: "1.0"))
        #expect(ReviewPrompt.isEligible(freedBytes: 1_200 * mb, priorDeletes: 3, lastAskedVersion: nil, currentVersion: "1.0"))
    }

    @Test func neverOnTheFirstEverDelete() {
        #expect(!ReviewPrompt.isEligible(freedBytes: 900 * mb, priorDeletes: 0, lastAskedVersion: nil, currentVersion: "1.0"))
        #expect(ReviewPrompt.isEligible(freedBytes: 900 * mb, priorDeletes: 1, lastAskedVersion: nil, currentVersion: "1.0"))
    }

    @Test func onceperVersion() {
        #expect(!ReviewPrompt.isEligible(freedBytes: 900 * mb, priorDeletes: 2, lastAskedVersion: "1.0", currentVersion: "1.0"))
        #expect(ReviewPrompt.isEligible(freedBytes: 900 * mb, priorDeletes: 2, lastAskedVersion: "1.0", currentVersion: "1.1"))
    }

    // MARK: In the view model

    private let library = FakeLibrary()
    private let defaults = freshDefaults()
    private let entitlements = TestEntitlements(isUnlocked: false)

    /// A started deck with several deletes pending, the mock video among them.
    private func vmWithPile() async throws -> (FeedViewModel, small: [LibraryItem], big: LibraryItem) {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: entitlements, defaults: defaults)
        await vm.start()
        for _ in 0..<6 { vm.decide(.left) }
        let big = try #require(vm.pendingItems.first { $0.bytes >= ReviewPrompt.minimumFreedBytes })
        let small = vm.pendingItems.filter { $0.bytes < ReviewPrompt.minimumFreedBytes }
        try #require(!small.isEmpty)
        return (vm, small, big)
    }

    @Test func aBigSecondDeleteIsDueOnlyOnceThePileCloses() async throws {
        let (vm, small, big) = try await vmWithPile()
        await vm.deleteNow(small)
        vm.releaseReviewPrompt()
        #expect(!vm.isReviewPromptDue, "Small, and the first delete")

        await vm.deleteNow([big])
        #expect(!vm.isReviewPromptDue, "Not while the freed confirmation shows")
        vm.releaseReviewPrompt()
        #expect(vm.isReviewPromptDue)

        vm.finishReviewPrompt(asked: true)
        #expect(!vm.isReviewPromptDue)
        #expect(defaults.string(forKey: DefaultsKey.reviewPromptVersion) == AppInfo.version)
    }

    @Test func aBigFirstEverDeleteDoesNotAsk() async throws {
        let (vm, _, big) = try await vmWithPile()

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isReviewPromptDue)
        #expect(defaults.integer(forKey: DefaultsKey.deleteCount) == 1)
    }

    @Test func alreadyAskedThisVersionDoesNotAskAgain() async throws {
        defaults.set(AppInfo.version, forKey: DefaultsKey.reviewPromptVersion)
        let (vm, small, big) = try await vmWithPile()
        await vm.deleteNow(small)

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isReviewPromptDue)
    }

    @Test func neverRightAfterAPurchase() async throws {
        let (vm, small, big) = try await vmWithPile()
        await vm.deleteNow(small)
        #expect(await vm.purchaseUnlock())

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isReviewPromptDue)
    }

    @Test func aSkippedPromptIsNotRecorded() async throws {
        let (vm, small, big) = try await vmWithPile()
        await vm.deleteNow(small)
        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        vm.finishReviewPrompt(asked: false)

        #expect(!vm.isReviewPromptDue)
        #expect(defaults.string(forKey: DefaultsKey.reviewPromptVersion) == nil)
    }
}
