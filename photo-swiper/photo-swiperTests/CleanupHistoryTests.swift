import Foundation
import Testing
@testable import photo_swiper

/// The cleanup history behind the dashboard: what a delete from the pile records, and what it never does.
@MainActor
struct CleanupHistoryTests {
    private let session = MockFeedBuilder().makeSessionNow(number: 1)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(_ kind: ProgressStoreTests.Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    // MARK: Store contract

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func recordedEntriesComeBackOldestFirst(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let newer = CleanupEntry(at: now, category: .video, count: 1, bytes: 800)
        let older = CleanupEntry(at: now.addingTimeInterval(-60), category: .duplicate, count: 3, bytes: 300)

        store.recordCleanup([newer])
        store.recordCleanup([older])

        #expect(store.cleanupHistory() == [older, newer])
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aDecisionKeepsItsCategory(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let item = session.items[0]
        store.save([item.id: StoredDecision(decision: .delete, decidedAt: now, sessionNumber: 1, item: item, category: .similar)])
        #expect(store.decisions(for: [item.id])[item.id]?.category == .similar)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func deletesFromBeforeTheHistoryAreFilledInOnce(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let items = Array(session.items.prefix(2))
        store.save(Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, StoredDecision(decision: .delete, decidedAt: now, sessionNumber: 1, item: $0))
        }))
        store.settle(Set(items.map(\.id)), as: .deleted)

        let history = store.cleanupHistory()
        #expect(history.reduce(0) { $0 + $1.bytes } == store.freedBytes())
        #expect(history.reduce(0) { $0 + $1.count } == 2)

        let next = CleanupEntry(at: .now.addingTimeInterval(60), category: .video, count: 1, bytes: 10)
        store.recordCleanup([next])
        #expect(store.cleanupHistory() == history + [next], "The fill-in never runs twice")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func resetForgetsTheHistory(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.recordCleanup([CleanupEntry(at: now, category: .photo, count: 1, bytes: 1)])
        store.reset()
        #expect(store.cleanupHistory().isEmpty)
    }

    @Test func entriesGroupByCategoryInAFixedOrder() {
        let items = Array(session.items.prefix(4))
        let categories: [LibraryItem.ID: CleanupCategory] = [
            items[0].id: .video, items[1].id: .duplicate, items[2].id: .video, items[3].id: .photo,
        ]
        let entries = CleanupEntry.entries(for: items, at: now) { categories[$0.id]! }

        #expect(entries.map(\.category) == [.duplicate, .video, .photo])
        #expect(entries[1].count == 2)
        #expect(entries[1].bytes == items[0].bytes + items[2].bytes)
    }

    // MARK: Deleting from the pile

    private func started(_ library: FakeLibrary, store: any ProgressStoring) async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), store: store,
                               entitlements: TestEntitlements(), defaults: freshDefaults(), now: { now })
        await vm.start()
        return vm
    }

    /// The mock deck starts photo, photo, photo, video.
    @Test func aDeleteRecordsWhatWasDeletedByCategory() async throws {
        let store = InMemoryProgressStore()
        let library = FakeLibrary()
        let vm = await started(library, store: store)
        for _ in 0..<4 { vm.decideCurrent(.left) }
        let pending = vm.pendingItems
        try #require(pending.count == 4)

        _ = await vm.deleteNow(pending)

        let video = try #require(pending.first { $0.isVideo })
        let photos = pending.filter { !$0.isVideo }
        #expect(store.cleanupHistory() == [
            CleanupEntry(at: now, category: .video, count: 1, bytes: video.bytes),
            CleanupEntry(at: now, category: .photo, count: 3, bytes: photos.reduce(0) { $0 + $1.bytes }),
        ])
        #expect(store.cleanupHistory().reduce(0) { $0 + $1.bytes } == vm.freedBytes)
    }

    @Test func onlyItemsActuallyDeletedAreRecorded() async throws {
        let store = InMemoryProgressStore()
        let library = FakeLibrary()
        let vm = await started(library, store: store)
        for _ in 0..<3 { vm.decideCurrent(.left) }
        let pending = vm.pendingItems
        library.onDelete = { items in
            DeletionOutcome(deleted: [items[0].id], missing: [items[1].id], undeletable: [items[2].id])
        }

        _ = await vm.deleteNow(pending)

        #expect(store.cleanupHistory() == [CleanupEntry(at: now, category: .photo, count: 1, bytes: pending[0].bytes)])
    }

    @Test func aCancelledDeleteRecordsNothing() async {
        let store = InMemoryProgressStore()
        let library = FakeLibrary()
        library.onDelete = { _ in throw DeletionError.cancelled }
        let vm = await started(library, store: store)
        for _ in 0..<3 { vm.decideCurrent(.left) }

        #expect(await vm.deleteNow(vm.pendingItems) == nil)
        #expect(store.cleanupHistory().isEmpty)
    }

    @Test func aGroupCardFilesItsItemsUnderTheGroup() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(FakeLibrary(), store: store)
        // The mock deck's first similar-shots card is at 6.
        func isSimilar(_ card: FeedCard?) -> Bool {
            if case .similar = card { true } else { false }
        }
        while vm.currentCard != nil, !isSimilar(vm.currentCard) { vm.decideCurrent(.right) }
        let card = try #require(vm.currentCard)
        vm.decideCurrent(.left)

        let saved = store.decisions(for: Set(card.items.map(\.id)))
        #expect(!saved.isEmpty)
        #expect(saved.values.allSatisfy { $0.category == .similar })
    }
}
