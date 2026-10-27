import Foundation
import SwiftData
import Testing
@testable import photo_swiper

/// A mock builder that remembers the options each page was built with.
private final class RecordingBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var requests: [FeedOptions] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        requests.append(options)
        return MockFeedBuilder().makeSessionNow(number: number, options: options)
    }
}

/// Builds mock pages, or nothing while `isExhausted`, to stand for a fully reviewed library.
private final class ExhaustingBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var requests: [FeedOptions] = []
    var isExhausted = false

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        requests.append(options)
        return isExhausted ? Session(number: number, cards: []) : MockFeedBuilder().makeSessionNow(number: number, options: options)
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

    private func launch(_ store: any ProgressStoring) async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: builder, store: store, entitlements: TestEntitlements(), now: { [clock] in clock })
        await vm.start()
        return vm
    }

    /// Keeps swiping right, letting each page land, until `done`.
    private func swipe(_ vm: FeedViewModel, until done: (FeedViewModel) -> Bool) async throws {
        for _ in 0..<500 {
            if done(vm) { return }
            vm.decide(.right)
            await vm.waitForPage()
        }
        Issue.record("Never got there")
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
        #expect(builder.requests.count == 1, "Relaunching resumes instead of building a new page")
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
        vm.saveDraft(draft, for: batch.id)

        let relaunched = await launch(store)

        #expect(relaunched.currentCard?.id == batch.id)
        #expect(relaunched.draft(for: batch.id) == draft)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aBatchDraftSavedByBatchIDStillLoads(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        while vm.phase == .feed, !{ if case .batch = vm.currentCard { true } else { false } }() { vm.decide(.right) }
        guard case .batch(let batch) = try #require(vm.currentCard), let session = vm.session else {
            Issue.record("Expected a batch card on top")
            return
        }
        // As saved before drafts were keyed by card: by the batch's own ID.
        let draft = [batch.items[0].id: Decision.delete]
        store.saveSession(SavedSession(session: session, index: vm.index, marks: [:], finished: false, drafts: [batch.id: draft]))

        let relaunched = await launch(store)

        #expect(relaunched.draft(for: FeedCard.batch(batch).id) == draft)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aPartialSimilarReviewSurvivesARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        while vm.phase == .feed, !{ if case .similar = vm.currentCard { true } else { false } }() { vm.decide(.right) }
        guard case .similar(let group) = try #require(vm.currentCard) else {
            Issue.record("Expected a similar card on top")
            return
        }
        let draft = [group.bestID: Decision.delete]
        vm.saveDraft(draft, for: group.id)

        let relaunched = await launch(store)

        #expect(relaunched.draft(for: group.id) == draft)
        #expect(relaunched.markedForClearing(in: group).contains(group.bestID))
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aCancelledDeleteStaysPendingAfterARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        library.onDelete = { _ in throw DeletionError.cancelled }
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        #expect(await vm.deleteNow(vm.pendingItems) == nil)

        let relaunched = await launch(store)

        #expect(relaunched.pendingItems.map(\.id) == vm.pendingItems.map(\.id))
        #expect(relaunched.pendingItems.count == 3)
        #expect(relaunched.freedBytes == 0)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func deletesAddToFreedAndLeaveThePileForGood(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        let freed = vm.pendingBytes
        #expect(await vm.deleteNow(vm.pendingItems) == freed)
        #expect(vm.freedBytes == freed)
        #expect(vm.phase == .feed, "Deleting never moves the deck")
        #expect(vm.index == 3)

        let relaunched = await launch(store)
        #expect(relaunched.phase == .feed)
        #expect(relaunched.index == 3)
        #expect(relaunched.freedBytes == freed)
        #expect(relaunched.pendingItems.isEmpty)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func itemsDeletedWhileClosedLeaveTheDeckAndThePile(_ kind: ProgressStoreTests.Kind) async throws {
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

        // The pruned deck itself is saved.
        library.gone = []
        let again = await launch(store)
        #expect(again.cards.map(\.id) == relaunched.cards.map(\.id))
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func pagesLeaveOutEverythingInTheDeckAndEverythingDecided(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        // From a page this deck won't reach.
        let earlier = MockFeedBuilder().makeSessionNow(number: MockFeedBuilder.pageCount).items[0]
        store.save([earlier.id: StoredDecision(decision: .keep, decidedAt: clock, sessionNumber: 0, item: earlier)])
        let vm = await launch(store)
        let firstPage = Set(vm.cards.flatMap(\.items).map(\.id))
        try await swipe(vm, until: { $0.cards.count > MockFeedBuilder.cardsPerSession })

        let excluded = try #require(builder.requests.last).excluding
        #expect(excluded.isSuperset(of: firstPage))
        #expect(excluded.contains(earlier.id))
        let ids = vm.cards.flatMap(\.items).map(\.id)
        #expect(Set(ids).count == ids.count, "No item is dealt twice")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func laterItemsReturnAfterADayWhenCheckingAgain(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let clock = TestClock(self.clock)
        let exhausting = ExhaustingBuilder()
        let vm = FeedViewModel(library: library, builder: exhausting, store: store, entitlements: TestEntitlements(), now: { clock.now })
        await vm.start()
        let kept = vm.cards[0].items[0].id, later = vm.cards[1].items[0].id, deleted = vm.cards[2].items[0].id
        vm.decide(.right)
        vm.decide(.up)
        vm.decide(.left)
        exhausting.isExhausted = true
        while vm.currentCard != nil { vm.decide(.right) }
        await vm.waitForPage()
        #expect(vm.phase == .caughtUp)

        clock.advance(hours: 1)
        await vm.checkAgain()
        #expect(vm.phase == .caughtUp, "Nothing turned up")
        let early = try #require(exhausting.requests.last).excluding
        #expect(early.isSuperset(of: [kept, later, deleted]))

        exhausting.isExhausted = false
        clock.advance(hours: 24)
        await vm.checkAgain()
        #expect(vm.phase == .feed)
        let late = try #require(exhausting.requests.last).excluding
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
        #expect(vm.decisions.isEmpty, "A later from an earlier deck isn't decided in this one")

        vm.decide(.left)
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .delete)
        vm.undo()

        #expect(store.decisions(for: [item.id])[item.id] == earlier)
        #expect(vm.pendingItems.isEmpty)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aDeckSavedWithEveryCardDecidedDealsTheNextPageOnLaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        // Synchronous swipes outrun paging, so the deck is saved with nothing ahead.
        while vm.currentCard != nil { vm.decide(.right) }
        #expect(vm.isFindingMore)

        let relaunched = await launch(store)

        #expect(relaunched.phase == .feed)
        #expect(relaunched.index == MockFeedBuilder.cardsPerSession)
        let firstPage = Set(vm.cards.map(\.id))
        #expect(relaunched.currentCard.map { !firstPage.contains($0.id) } == true, "A new page, not the old one again")
        #expect(relaunched.cards.count == 2 * MockFeedBuilder.cardsPerSession)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func theLastPageRunningOutIsCaughtUpAndStaysThatWay(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        try await swipe(vm, until: { $0.phase == .caughtUp })
        #expect(vm.session?.number == MockFeedBuilder.pageCount, "Every mock page was dealt, then nothing")

        let relaunched = await launch(store)
        #expect(relaunched.phase == .caughtUp)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func pendingDeletesTrimmedFromBehindTheDeckStayInThePile(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        for _ in 0..<3 { vm.decide(.left) }
        let early = vm.pendingItems.map(\.id)
        // Once deep enough into the deck, the first cards are let go.
        try await swipe(vm, until: { vm in !vm.cards.contains { $0.items.contains { $0.id == early[0] } } })
        vm.decide(.left)
        let current = try #require(vm.pendingItems.last)
        #expect(Array(vm.pendingItems.map(\.id).prefix(3)) == early, "Trimmed deletes are still pending")

        let carried = try #require(vm.pendingItems.first)
        #expect(await vm.deleteNow([carried, current]) == carried.bytes + current.bytes)
        let stillPending = Set(vm.pendingItems.map(\.id))
        #expect(stillPending.isSuperset(of: early.dropFirst()))
        let relaunched = await launch(store)
        #expect(Set(relaunched.pendingItems.map(\.id)) == stillPending)
        #expect(relaunched.freedBytes == carried.bytes + current.bytes)

        relaunched.keep(relaunched.pendingItems)
        let again = await launch(store)
        #expect(again.pendingItems.isEmpty)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func skipFavoritesIsRemembered(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        vm.skipFavorites = false

        let relaunched = await launch(store)
        #expect(relaunched.skipFavorites == false)
    }

    /// A deck saved while the Forwarded batch existed can't be decoded. It's dropped, not a crash,
    /// and the next launch deals a fresh deck while saved decisions stay put.
    @Test func aSavedSessionWithARemovedCardKindStartsFresh() async throws {
        let container = try SwiftDataProgressStore.makeContainer(inMemory: true)
        let store = SwiftDataProgressStore(container: container, defaults: nil)
        let vm = await launch(store)
        vm.decide(.left)
        let decided = try #require(vm.cards.first?.items.first)

        let row = try #require(try container.mainContext.fetch(FetchDescriptor<SessionProgress>()).first)
        let json = try #require(String(data: row.snapshot, encoding: .utf8))
        #expect(json.contains(#"{"screenshots":{}}"#))
        row.snapshot = Data(json.replacingOccurrences(of: #"{"screenshots":{}}"#, with: #"{"forwarded":{}}"#).utf8)
        try container.mainContext.save()

        #expect(store.loadSession() == nil)
        let relaunched = await launch(store)
        #expect(relaunched.phase == .feed)
        #expect(builder.requests.count == 2, "A new deck was built")
        #expect(store.decisions(for: [decided.id])[decided.id]?.decision == .delete)
    }
}
