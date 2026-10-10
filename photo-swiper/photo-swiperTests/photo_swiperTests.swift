//
//  photo_swiperTests.swift
//  photo-swiperTests
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

import Foundation
import Testing
@testable import photo_swiper

/// A library whose access, delete results, and outside changes the test controls.
final class FakeLibrary: PhotoLibraryProviding, @unchecked Sendable {
    var access = LibraryAccess.full
    var onDelete: ([LibraryItem]) throws -> DeletionOutcome = { DeletionOutcome(deleted: $0.map(\.id)) }
    /// Items gone from the library, as reported to launch-time reconciliation.
    var gone: Set<LibraryItem.ID> = []
    private var listeners: [AsyncStream<Set<LibraryItem.ID>>.Continuation] = []

    func requestAccess() async -> LibraryAccess { access }
    func stats() async -> LibraryStats { LibraryStats(totalItems: 100, reviewedItems: 0, freedBytes: 0) }
    func delete(_ items: [LibraryItem]) async throws -> DeletionOutcome { try onDelete(items) }
    func vanishedItems() -> AsyncStream<Set<LibraryItem.ID>> {
        let (stream, continuation) = AsyncStream.makeStream(of: Set<LibraryItem.ID>.self)
        listeners.append(continuation)
        return stream
    }
    func missing(from ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> { ids.intersection(gone) }

    /// Simulates items deleted outside the app while it runs.
    func vanish(_ ids: Set<LibraryItem.ID>) {
        for listener in listeners { listener.yield(ids) }
    }
}

@MainActor
struct FeedViewModelLibraryTests {
    private let library = FakeLibrary()

    private func started() async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder())
        await vm.start()
        return vm
    }

    /// Lets the view model's change-observing task run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func deniedAccessShowsNoAccess() async {
        library.access = .denied
        let vm = await started()
        #expect(vm.phase == .noAccess)
        #expect(vm.session == nil)
    }

    @Test func cancellingTheSystemPromptKeepsEverythingPending() async {
        library.onDelete = { _ in throw DeletionError.cancelled }
        let vm = await started()
        for _ in 0..<3 { vm.decide(.left) }

        #expect(await vm.confirmDelete() == false)
        #expect(vm.pendingItems.count == 3)
        #expect(vm.freedBytes == 0)
        #expect(vm.celebration == nil)
        #expect(vm.deleteNotice == nil)
    }

    @Test func onlyActuallyDeletedItemsCountAsFreed() async {
        let vm = await started()
        for _ in 0..<3 { vm.decide(.left) }
        let pending = vm.pendingItems
        library.onDelete = { items in
            DeletionOutcome(deleted: [items[0].id], missing: [items[1].id], undeletable: [items[2].id])
        }

        #expect(await vm.confirmDelete())
        #expect(vm.freedBytes == pending[0].bytes)
        #expect(vm.celebration?.count == 1)
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.deleteNotice != nil)
    }

    @Test func failedDeleteRemovesNothing() async {
        library.onDelete = { _ in throw DeletionError.failed(CocoaError(.fileWriteUnknown)) }
        let vm = await started()
        vm.decide(.left)

        #expect(await vm.confirmDelete() == false)
        #expect(vm.pendingItems.count == 1)
        #expect(vm.deleteNotice != nil)
    }

    @Test func deletingNowClearsOnlyThoseAndKeepsTheSessionGoing() async throws {
        let vm = await started()
        for _ in 0..<3 { vm.decide(.left) }
        let deleted = try #require(vm.pendingItems.first)
        var asked: [LibraryItem.ID] = []
        library.onDelete = { items in
            asked = items.map(\.id)
            return DeletionOutcome(deleted: items.map(\.id))
        }

        #expect(await vm.deleteNow([deleted]))
        #expect(asked == [deleted.id], "Only the chosen photos are deleted")
        #expect(vm.pendingItems.count == 2)
        #expect(!vm.pendingItems.contains { $0.id == deleted.id })
        #expect(vm.freedBytes == deleted.bytes)
        #expect(vm.phase == .feed)
        #expect(vm.celebration == nil)
        #expect(vm.canUndo == false, "A deleted photo can't be swiped back")

        let rest = vm.pendingItems
        #expect(await vm.confirmDelete())
        #expect(asked == rest.map(\.id))
        #expect(vm.celebration?.count == 2)
    }

    @Test func keepingTakesItemsOutOfThePileEvenAcrossUndo() async throws {
        let vm = await started()
        vm.decide(.left)
        vm.decide(.left)
        let kept = try #require(vm.pendingItems.first)
        let other = try #require(vm.pendingItems.last)

        vm.keep([kept])

        #expect(vm.pendingItems.map(\.id) == [other.id])
        #expect(vm.pendingBytes == other.bytes)
        #expect(vm.decisions[kept.id] == .keep)

        vm.undo()
        #expect(vm.pendingItems.isEmpty, "Undoing a later swipe doesn't bring it back")
        #expect(vm.decisions[kept.id] == .keep)
    }

    @Test func cancellingDeleteNowKeepsThemPending() async throws {
        library.onDelete = { _ in throw DeletionError.cancelled }
        let vm = await started()
        vm.decide(.left)

        #expect(await vm.deleteNow(vm.pendingItems) == false)
        #expect(vm.pendingItems.count == 1)
        #expect(vm.freedBytes == 0)
    }

    @Test func itemsDeletedOutsideTheAppLeaveUpcomingCardsAndThePile() async throws {
        let vm = await started()
        vm.decide(.left)
        let pendingID = try #require(vm.pendingItems.first?.id)
        let current = try #require(vm.currentCard)
        let upcomingPhoto = vm.cards[5]
        let batchIndex = try #require(vm.cards.firstIndex { if case .batch = $0 { true } else { false } })
        guard case .batch(let batch) = vm.cards[batchIndex] else { return }
        let countBefore = vm.cards.count

        library.vanish([pendingID, current.items[0].id, upcomingPhoto.items[0].id, batch.items[0].id])
        await settle { vm.cards.count < countBefore }

        #expect(vm.pendingItems.isEmpty)
        #expect(vm.currentCard?.id == current.id, "The card on screen stays put")
        #expect(vm.cards.count == countBefore - 1)
        #expect(!vm.cards.contains { $0.id == upcomingPhoto.id })
        let pruned = try #require(vm.cards.lazy.compactMap { if case .batch(let b) = $0, b.id == batch.id { b } else { nil } }.first)
        #expect(pruned.items.count == batch.items.count - 1)
        #expect(pruned.title.hasPrefix("\(batch.items.count - 1) "))
    }
}

@MainActor
struct BatchReviewTests {
    private func batchCard(_ vm: FeedViewModel) throws -> ItemBatch {
        guard case .batch(let batch) = try #require(vm.currentCard) else {
            Issue.record("Expected a batch card on top")
            throw CancellationError()
        }
        return batch
    }

    @Test func decidingOneByOneClearsOnlyTheDeletedItems() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let start = vm.index
        let batch = try batchCard(vm)
        let deleted = Array(batch.items.prefix(3))
        var outcome = Dictionary(uniqueKeysWithValues: batch.items.map { ($0.id, Decision.keep) })
        for item in deleted { outcome[item.id] = .delete }

        vm.decideIndividually(outcome)

        #expect(vm.index == start + 1)
        #expect(Set(vm.pendingItems.map(\.id)) == Set(deleted.map(\.id)))
        #expect(vm.pendingBytes == deleted.reduce(0) { $0 + $1.bytes })
        #expect(vm.keptCount == batch.items.count - deleted.count)
    }

    @Test func itemsLeftOutCountAsLater() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)

        vm.decideIndividually([batch.items[0].id: .delete])

        #expect(vm.pendingItems.map(\.id) == [batch.items[0].id])
        #expect(vm.laterCount == batch.items.count - 1)
    }

    @Test func undoRestoresTheWholeBatch() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let start = vm.index
        let batch = try batchCard(vm)

        vm.decideIndividually([batch.items[0].id: .delete, batch.items[1].id: .keep])
        vm.undo()

        #expect(vm.index == start)
        #expect(vm.currentCard?.id == batch.id)
        #expect(vm.decisions.isEmpty)
        #expect(vm.returningCard?.direction == .left)
    }

    @Test func swipingLeftAfterAPartialReviewClearsTheRestButKeepsDraftedKeeps() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)
        let kept = batch.items[0], deleted = batch.items[1]

        vm.saveDraft([kept.id: .keep, deleted.id: .delete], for: batch)
        vm.decide(.left)

        #expect(Set(vm.pendingItems.map(\.id)) == Set(batch.items.dropFirst().map(\.id)))
        #expect(vm.decisions[kept.id] == .keep)
        #expect(vm.draft(for: batch).isEmpty)
    }

    @Test func swipingRightAfterAPartialReviewStillClearsDraftedDeletes() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)
        let deleted = batch.items[0]

        vm.saveDraft([deleted.id: .delete], for: batch)
        #expect(vm.bytesToClear(for: .batch(batch)) == batch.items.reduce(0) { $0 + $1.bytes })
        vm.decide(.right)

        #expect(vm.pendingItems.map(\.id) == [deleted.id])
        #expect(vm.keptCount == batch.items.count - 1)
    }

    @Test func undoBringsBackTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)
        let draft = [batch.items[0].id: Decision.delete]

        vm.saveDraft(draft, for: batch)
        vm.decide(.up)
        vm.undo()

        #expect(vm.draft(for: batch) == draft)
        #expect(vm.decisions.isEmpty)
    }

    @Test func finishingTheReviewClearsTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)

        vm.saveDraft([batch.items[0].id: .delete], for: batch)
        vm.decideIndividually(Dictionary(uniqueKeysWithValues: batch.items.map { ($0.id, Decision.keep) }))

        #expect(vm.draft(for: batch).isEmpty)
        #expect(vm.pendingItems.isEmpty)
    }

    @Test func ignoredWhenTheTopCardIsNotABatch() throws {
        let vm = FeedViewModel.mock(startingAt: .first)
        let item = try #require(vm.currentCard?.items.first)

        vm.decideIndividually([item.id: .delete])

        #expect(vm.index == 0)
        #expect(vm.decisions.isEmpty)
    }
}

struct SessionCodingTests {
    @Test func sessionsRoundTripThroughJSON() throws {
        let session = MockFeedBuilder().makeSessionNow(number: 2, options: FeedOptions(skipFavorites: false))
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }
}
