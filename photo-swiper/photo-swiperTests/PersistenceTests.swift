import Foundation
import Testing
@testable import photo_swiper

/// A mock builder that remembers the options each session was built with.
private final class RecordingBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var requests: [FeedOptions] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        requests.append(options)
        return MockFeedBuilder().makeSessionNow(number: number, options: options)
    }
}

/// "Relaunching" means a new view model on the same store, as after a force-quit.
@MainActor
struct FeedViewModelPersistenceTests {
    private let library = FakeLibrary()
    private let builder = RecordingBuilder()
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(_ kind: ProgressStoreTests.Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    private func launch(_ store: any ProgressStoring, at date: Date? = nil) async -> FeedViewModel {
        let now = date ?? clock
        let vm = FeedViewModel(library: library, builder: builder, store: store, now: { now })
        await vm.start()
        return vm
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func decisionsIndexAndMarksSurviveARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for direction: SwipeDirection in [.left, .right, .up, .right, .left, .left] { vm.decide(direction) }
        guard case .similar(let group) = try #require(vm.currentCard) else {
            Issue.record("Expected the similar group on top")
            return
        }
        vm.toggleMark(group.items[1].id, in: group)

        let relaunched = await launch(store)

        #expect(relaunched.phase == .feed)
        #expect(relaunched.cards.map(\.id) == vm.cards.map(\.id))
        #expect(relaunched.index == vm.index)
        #expect(relaunched.decisions == vm.decisions)
        #expect(relaunched.markedForClearing(in: group) == vm.markedForClearing(in: group))
        #expect(relaunched.pendingItems.map(\.id) == vm.pendingItems.map(\.id))
        #expect(relaunched.libraryReviewedCount == 5)
        #expect(!relaunched.canUndo)
        #expect(builder.requests.count == 1, "Relaunching resumes instead of building a new session")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aPartialBatchReviewSurvivesARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        while vm.phase == .feed, !{ if case .batch = vm.currentCard { true } else { false } }() { vm.decide(.right) }
        guard case .batch(let batch) = try #require(vm.currentCard) else {
            Issue.record("Expected a batch card on top")
            return
        }
        let draft = [batch.items[0].id: Decision.delete, batch.items[1].id: .keep]
        vm.saveDraft(draft, for: batch)

        let relaunched = await launch(store)

        #expect(relaunched.currentCard?.id == batch.id)
        #expect(relaunched.draft(for: batch) == draft)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aCancelledDeleteStaysPendingAfterARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        library.onDelete = { _ in throw DeletionError.cancelled }
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        #expect(await vm.confirmDelete() == false)

        let relaunched = await launch(store)

        #expect(relaunched.pendingItems.map(\.id) == vm.pendingItems.map(\.id))
        #expect(relaunched.pendingItems.count == 3)
        #expect(relaunched.freedBytes == 0)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func confirmedDeletesAddToFreedAndLeaveThePileForGood(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        let freed = vm.pendingBytes
        #expect(await vm.confirmDelete())
        #expect(vm.freedBytes == freed)

        let relaunched = await launch(store)
        #expect(relaunched.phase == .caughtUp)
        #expect(relaunched.freedBytes == freed)
        #expect(relaunched.pendingItems.isEmpty)

        await relaunched.startNewSession()
        #expect(relaunched.pendingItems.isEmpty)
        #expect(relaunched.freedBytes == freed)
        #expect(relaunched.session?.number == 2)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func itemsDeletedWhileClosedLeaveTheSessionAndThePile(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        vm.decide(.left)
        let first = vm.cards[0], second = vm.cards[1], upcoming = vm.cards[5]
        guard case .batch(let batch) = vm.cards[8] else {
            Issue.record("Expected a batch at card 9")
            return
        }
        library.gone = [first.items[0].id, upcoming.items[0].id, batch.items[0].id]

        let relaunched = await launch(store)

        #expect(relaunched.pendingItems.isEmpty)
        #expect(relaunched.index == 0, "The decided card before it was pruned")
        #expect(relaunched.currentCard?.id == second.id)
        #expect(relaunched.cards.count == vm.cards.count - 2)
        #expect(!relaunched.cards.contains { $0.id == upcoming.id })
        let pruned = relaunched.cards.lazy.compactMap { if case .batch(let b) = $0, b.id == batch.id { b } else { nil } }.first
        #expect(pruned?.items.count == batch.items.count - 1)

        // The pruned session itself is saved.
        library.gone = []
        let again = await launch(store)
        #expect(again.cards.map(\.id) == relaunched.cards.map(\.id))
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func decidedItemsStayOutAndLaterOnesReturnAfterADay(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        let kept = vm.cards[0].items[0].id, later = vm.cards[1].items[0].id, deleted = vm.cards[2].items[0].id
        vm.decide(.right)
        vm.decide(.up)
        vm.decide(.left)
        vm.finishForNow()

        let soon = await launch(store, at: clock.addingTimeInterval(3600))
        await soon.startNewSession()
        let early = try #require(builder.requests.last).excluding
        #expect(early.isSuperset(of: [kept, later, deleted]))

        let nextDay = await launch(store, at: clock.addingTimeInterval(25 * 3600))
        await nextDay.startNewSession()
        let late = try #require(builder.requests.last).excluding
        #expect(late.isSuperset(of: [kept, deleted]))
        #expect(!late.contains(later))
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func undoingAReturningLaterItemPutsItBackToLater(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let item = MockFeedBuilder().makeSessionNow(number: 1).items[0]
        let earlier = StoredDecision(decision: .later, decidedAt: clock.addingTimeInterval(-2 * 86_400), sessionNumber: 0, item: item)
        store.save([item.id: earlier])
        let vm = await launch(store)
        #expect(vm.decisions.isEmpty, "A later from an earlier session isn't decided in this one")

        vm.decide(.left)
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .delete)
        vm.undo()

        #expect(store.decisions(for: [item.id])[item.id] == earlier)
        #expect(vm.pendingItems.isEmpty)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func doneForNowResumesCaughtUp(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        while vm.phase == .feed { vm.decide(.right) }
        vm.finishForNow()

        let relaunched = await launch(store)

        #expect(relaunched.phase == .caughtUp)
        await relaunched.startNewSession()
        #expect(relaunched.session?.number == 2)
        #expect(relaunched.phase == .feed)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func unconfirmedDeletesResumeAtTheEndOfTheSession(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        while vm.phase == .feed { vm.decide(.left) }

        let relaunched = await launch(store)

        #expect(relaunched.phase == .endOfSession)
        #expect(relaunched.pendingItems.map(\.id) == vm.pendingItems.map(\.id))
        #expect(relaunched.pendingBytes == vm.pendingBytes)

        // Moving on carries the unconfirmed pile into the next session.
        await relaunched.startNewSession()
        #expect(Set(relaunched.pendingItems.map(\.id)) == Set(vm.pendingItems.map(\.id)))
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func deletedNowStaysOutOfThePileAfterARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        await vm.startNewSession()
        vm.decide(.left)
        // One carried from the first session, one from this one.
        let carried = try #require(vm.pendingItems.first)
        let current = try #require(vm.pendingItems.last)
        #expect(await vm.deleteNow([carried, current]))

        let relaunched = await launch(store)

        #expect(relaunched.pendingItems.count == 2)
        #expect(!relaunched.pendingItems.contains { $0.id == carried.id || $0.id == current.id })
        #expect(relaunched.freedBytes == carried.bytes + current.bytes)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func keptStaysOutOfThePileAfterARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        await vm.startNewSession()
        vm.decide(.left)
        // One carried from the first session, one from this one.
        let carried = try #require(vm.pendingItems.first)
        let current = try #require(vm.pendingItems.last)
        vm.keep([carried, current])

        let relaunched = await launch(store)

        #expect(relaunched.pendingItems.count == 2)
        #expect(!relaunched.pendingItems.contains { $0.id == carried.id || $0.id == current.id })
        #expect(relaunched.decisions[current.id] == .keep)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func skipFavoritesIsRemembered(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        vm.skipFavorites = false

        let relaunched = await launch(store)
        #expect(relaunched.skipFavorites == false)
    }
}
