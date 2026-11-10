import Foundation
import Testing
@testable import photo_swiper

/// "N of M photos reviewed": each item counts once, only while it's still in the library,
/// never more than the total. And the confetti at 100%.
@MainActor
struct LibraryProgressTests {
    private let library = FakeLibrary()
    private let defaults = freshDefaults()
    private let store = InMemoryProgressStore()

    private func started() async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), store: store,
                               entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        return vm
    }

    private func isSingle(_ card: FeedCard?) -> Bool {
        switch card {
        case .photo, .video: true
        default: false
        }
    }

    /// Swipes right until a card like this is on top.
    private func advance(_ vm: FeedViewModel, to match: (FeedCard) -> Bool) async throws -> FeedCard {
        for _ in 0..<200 {
            if let card = vm.currentCard, match(card) { return card }
            vm.decideCurrent(.right)
            await vm.waitForPage()
        }
        throw CardNotFound()
    }

    private struct CardNotFound: Error {}

    /// Lets the view model's change-observing task run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Counting

    @Test func laterIsNotReviewed() async throws {
        let vm = await started()
        vm.decideCurrent(.up)
        #expect(vm.libraryReviewedCount == 0)
        #expect(vm.laterCount > 0)

        let next = try #require(vm.currentCard)
        vm.decideCurrent(.right)
        #expect(vm.libraryReviewedCount == next.items.count)
    }

    @Test func undoThenRedoCountsOnce() async throws {
        let vm = await started()
        let card = try #require(vm.currentCard)
        vm.decideCurrent(.right)
        #expect(vm.libraryReviewedCount == card.items.count)

        vm.undo()
        #expect(vm.libraryReviewedCount == 0)

        vm.decideCurrent(.right)
        #expect(vm.libraryReviewedCount == card.items.count)
        vm.undo()
        vm.decideCurrent(.left)
        #expect(vm.libraryReviewedCount == card.items.count, "Changing the answer doesn't add it again")
    }

    @Test func seenTwiceCountsOnce() async throws {
        let vm = await started()
        let card = try await advance(vm, to: { isSingle($0) })
        let before = vm.libraryReviewedCount
        vm.decideCurrent(.left)
        #expect(vm.libraryReviewedCount == before + 1)

        // Seen again in the pile and kept instead.
        vm.keep(card.items)
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.libraryReviewedCount == before + 1)
    }

    @Test func bundleAndItsSubFeedCountOnce() async throws {
        let vm = await started()
        let card = try await advance(vm, to: { if case .batch = $0 { true } else { false } })
        let before = vm.libraryReviewedCount

        // One by one, partway: only a draft, nothing reviewed yet.
        let partial = Dictionary(uniqueKeysWithValues: card.items.prefix(2).map { ($0.id, Decision.delete) })
        vm.saveDraft(partial, for: card.id)
        #expect(vm.libraryReviewedCount == before)

        // Finished: each item once, though the bundle and its review both showed it.
        let all = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, Decision.keep) })
        vm.decideCurrentIndividually(all)
        #expect(vm.currentCard?.id != card.id)
        #expect(vm.libraryReviewedCount == before + card.items.count)
    }

    @Test func itemsDeletedHereStopCounting() async throws {
        let vm = await started()
        _ = try await advance(vm, to: { isSingle($0) })
        vm.decideCurrent(.left)
        _ = try await advance(vm, to: { isSingle($0) })
        vm.decideCurrent(.left)
        let pending = vm.pendingItems
        #expect(pending.count == 2)
        let before = vm.libraryReviewedCount

        library.totalItems = 100 - pending.count
        await vm.deleteNow(pending)

        #expect(vm.libraryReviewedCount == before - pending.count)
        #expect(vm.stats.totalItems == 100 - pending.count, "The total is read again")
        #expect(vm.libraryReviewedCount <= vm.stats.totalItems)
    }

    @Test func itemsDeletedElsewhereStopCounting() async throws {
        let vm = await started()
        let card = try #require(vm.currentCard)
        vm.decideCurrent(.right)
        #expect(vm.libraryReviewedCount == card.items.count)

        library.totalItems = 100 - card.items.count
        library.vanish(Set(card.items.map(\.id)))
        await settle { vm.stats.totalItems < 100 }

        #expect(vm.libraryReviewedCount == 0)
        #expect(vm.stats.totalItems == 100 - card.items.count)
    }

    @Test func neverMoreThanTheTotal() async throws {
        library.totalItems = 3
        let vm = await started()
        for _ in 0..<6 { vm.decideCurrent(.right) }
        #expect(store.reviewedCount() > 3)
        #expect(vm.libraryReviewedCount == 3)
        #expect(vm.libraryReviewedFraction == 1)
    }

    @Test func mockBaselineIsNotAddedToSwipes() {
        let vm = FeedViewModel.mock()
        #expect(vm.libraryReviewedCount == MockPhotoLibrary().reviewedItems)
        vm.decideCurrent(.right)
        #expect(vm.libraryReviewedCount == MockPhotoLibrary().reviewedItems)
    }

    // MARK: Celebration

    @Test func celebratesOncePerHundredPercent() async throws {
        library.totalItems = 1
        let vm = await started()
        #expect(!vm.isCompleteCelebrationDue)

        vm.decideCurrent(.right)
        #expect(vm.isLibraryComplete)
        #expect(vm.isCompleteCelebrationDue)

        vm.markCompleteCelebrated()
        #expect(!vm.isCompleteCelebrationDue)
        #expect(defaults.bool(forKey: DefaultsKey.celebratedComplete))

        // Remembered across launches.
        let relaunched = await started()
        #expect(relaunched.isLibraryComplete)
        #expect(!relaunched.isCompleteCelebrationDue)

        // Below 100% again, so the next 100% celebrates again.
        vm.undo()
        #expect(!vm.isLibraryComplete)
        #expect(!vm.hasCelebratedComplete)
        #expect(!defaults.bool(forKey: DefaultsKey.celebratedComplete))
        vm.decideCurrent(.right)
        #expect(vm.isCompleteCelebrationDue)
    }

    @Test func simulatedCompleteIsDisplayOnly() async throws {
        let vm = await started()
        vm.decideCurrent(.up)
        let saved = store.decisions(for: Set(vm.decisions.keys))

        vm.admin.debugSetSimulatesComplete(true)
        #expect(vm.libraryReviewedCount == vm.stats.totalItems)
        #expect(vm.libraryReviewedFraction == 1)
        #expect(vm.isCompleteCelebrationDue)
        #expect(store.reviewedCount() == 0, "Nothing is saved")
        #expect(store.decisions(for: Set(vm.decisions.keys)) == saved)

        vm.admin.debugSetSimulatesComplete(false)
        #expect(vm.libraryReviewedCount == 0, "The real numbers come straight back")
        #expect(vm.libraryReviewedFraction == 0)
    }

    @Test func debugResetCelebrationClearsTheFlag() async throws {
        let vm = await started()
        vm.admin.debugSetSimulatesComplete(true)
        vm.markCompleteCelebrated()
        #expect(!vm.isCompleteCelebrationDue)

        vm.admin.debugResetCelebration()
        #expect(vm.isCompleteCelebrationDue)
        #expect(!defaults.bool(forKey: DefaultsKey.celebratedComplete))

        let before = vm.celebrationRequest
        vm.admin.debugPlayCelebration()
        #expect(vm.celebrationRequest == before + 1)
    }
}

/// The count both stores give: unique items, keep or delete, still in the library.
@MainActor
struct ReviewedCountTests {
    private let session = MockFeedBuilder().makeSessionNow(number: 1)

    private func record(_ item: LibraryItem, _ decision: Decision) -> StoredDecision {
        StoredDecision(decision: decision, decidedAt: .now, sessionNumber: 1, item: item)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func eachItemCountsOnceWhileItsInTheLibrary(_ kind: ProgressStoreTests.Kind) throws {
        let store: any ProgressStoring = switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
        let items = Array(session.items.prefix(5))

        // Seen twice: later, then keep, then changed to delete.
        store.save([items[0].id: record(items[0], .later)])
        #expect(store.reviewedCount() == 0)
        store.save([items[0].id: record(items[0], .keep)])
        store.save([items[0].id: record(items[0], .delete)])
        #expect(store.reviewedCount() == 1)

        store.save([
            items[1].id: record(items[1], .delete),
            items[2].id: record(items[2], .delete),
            items[3].id: record(items[3], .keep),
            items[4].id: record(items[4], .delete),
        ])
        #expect(store.reviewedCount() == 5)

        store.settle([items[1].id], as: .deleted)
        store.settle([items[3].id], as: .gone)
        store.settle([items[4].id], as: .undeletable)
        #expect(store.reviewedCount() == 3, "Deleted and gone items leave; undeletable ones are still there")
    }
}
