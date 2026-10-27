//
//  photo_swiperTests.swift
//  photo-swiperTests
//
//  Created by Israel Avendano Jr. on 10/7/26.
//

import Foundation
import Observation
import Testing
@testable import photo_swiper

/// A library whose access, delete results, and outside changes the test controls.
final class FakeLibrary: PhotoLibraryProviding, @unchecked Sendable {
    var access = LibraryAccess.full
    /// True while the user hasn't been asked for access yet.
    var needsPrompt = false
    /// How many times the system prompt would have been shown.
    private(set) var requestCount = 0
    var onDelete: ([LibraryItem]) throws -> DeletionOutcome = { DeletionOutcome(deleted: $0.map(\.id)) }
    /// Items gone from the library, as reported to launch-time reconciliation.
    var gone: Set<LibraryItem.ID> = []
    private var listeners: [AsyncStream<Set<LibraryItem.ID>>.Continuation] = []

    func needsAccessPrompt() -> Bool { needsPrompt }
    func requestAccess() async -> LibraryAccess {
        requestCount += 1
        return access
    }
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

/// Entitlements the test controls. Unlocked by default, so tests about other things can run
/// as many sessions as they like.
@MainActor
@Observable
final class TestEntitlements: EntitlementStore {
    var isUnlocked: Bool
    let displayPrice = "$12.99"
    var unlockResult = true
    var restoreResult = RestoreOutcome.restored
    private(set) var restoreCount = 0
    private(set) var unlockCount = 0

    init(isUnlocked: Bool = true) {
        self.isUnlocked = isUnlocked
    }

    func unlock() async -> Bool {
        unlockCount += 1
        if unlockResult { isUnlocked = true }
        return unlockResult
    }

    func restore() async -> RestoreOutcome {
        restoreCount += 1
        if restoreResult == .restored { isUnlocked = true }
        return restoreResult
    }
}

/// A notification center that records instead of scheduling. Grants permission unless told not to.
@MainActor
final class FakeNotificationCenter: NotificationScheduling {
    var grants = true
    /// Notifications turned off in the Settings app.
    var denied = false
    private(set) var authorizationRequests = 0
    /// What's scheduled and not yet cancelled, by identifier.
    private(set) var pending: [String: RefillReminder] = [:]
    private(set) var added: [RefillReminder] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grants
    }

    func isDenied() async -> Bool {
        denied
    }

    func add(_ reminder: RefillReminder) async {
        added.append(reminder)
        pending[reminder.id] = reminder
    }

    func removePending(_ ids: [String]) {
        for id in ids { pending[id] = nil }
    }
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.now = now
    }

    func advance(hours: Double) {
        now = now.addingTimeInterval(hours * 3600)
    }
}

/// A fresh, empty defaults suite per test.
func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
struct FeedViewModelLibraryTests {
    private let library = FakeLibrary()

    private func started() async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: TestEntitlements())
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

        #expect(await vm.deleteNow(vm.pendingItems) == nil)
        #expect(vm.pendingItems.count == 3)
        #expect(vm.freedBytes == 0)
        #expect(vm.deleteNotice == nil)
    }

    @Test func onlyActuallyDeletedItemsCountAsFreed() async {
        let vm = await started()
        for _ in 0..<3 { vm.decide(.left) }
        let pending = vm.pendingItems
        library.onDelete = { items in
            DeletionOutcome(deleted: [items[0].id], missing: [items[1].id], undeletable: [items[2].id])
        }

        #expect(await vm.deleteNow(pending) == pending[0].bytes)
        #expect(vm.freedBytes == pending[0].bytes)
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.deleteNotice != nil)
    }

    @Test func failedDeleteRemovesNothing() async {
        library.onDelete = { _ in throw DeletionError.failed(CocoaError(.fileWriteUnknown)) }
        let vm = await started()
        vm.decide(.left)

        #expect(await vm.deleteNow(vm.pendingItems) == nil)
        #expect(vm.pendingItems.count == 1)
        #expect(vm.deleteNotice != nil)
    }

    @Test func deletingNowClearsOnlyThoseAndKeepsTheDeckGoing() async throws {
        let vm = await started()
        for _ in 0..<3 { vm.decide(.left) }
        let deleted = try #require(vm.pendingItems.first)
        var asked: [LibraryItem.ID] = []
        library.onDelete = { items in
            asked = items.map(\.id)
            return DeletionOutcome(deleted: items.map(\.id))
        }

        #expect(await vm.deleteNow([deleted]) == deleted.bytes)
        #expect(asked == [deleted.id], "Only the chosen photos are deleted")
        #expect(vm.pendingItems.count == 2)
        #expect(!vm.pendingItems.contains { $0.id == deleted.id })
        #expect(vm.freedBytes == deleted.bytes)
        #expect(vm.phase == .feed)
        #expect(vm.index == 3)
        #expect(vm.canUndo == false, "A deleted photo can't be swiped back")

        let rest = vm.pendingItems
        #expect(await vm.deleteNow(rest) == rest.reduce(0) { $0 + $1.bytes })
        #expect(asked == rest.map(\.id))
        #expect(vm.pendingItems.isEmpty)
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

        #expect(await vm.deleteNow(vm.pendingItems) == nil)
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

        vm.saveDraft([kept.id: .keep, deleted.id: .delete], for: batch.id)
        vm.decide(.left)

        #expect(Set(vm.pendingItems.map(\.id)) == Set(batch.items.dropFirst().map(\.id)))
        #expect(vm.decisions[kept.id] == .keep)
        #expect(vm.draft(for: batch.id).isEmpty)
    }

    @Test func swipingRightAfterAPartialReviewStillClearsDraftedDeletes() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)
        let deleted = batch.items[0]

        vm.saveDraft([deleted.id: .delete], for: batch.id)
        #expect(vm.bytesToClear(for: .batch(batch)) == batch.items.reduce(0) { $0 + $1.bytes })
        vm.decide(.right)

        #expect(vm.pendingItems.map(\.id) == [deleted.id])
        #expect(vm.keptCount == batch.items.count - 1)
    }

    @Test func undoBringsBackTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)
        let draft = [batch.items[0].id: Decision.delete]

        vm.saveDraft(draft, for: batch.id)
        vm.decide(.up)
        vm.undo()

        #expect(vm.draft(for: batch.id) == draft)
        #expect(vm.decisions.isEmpty)
    }

    @Test func finishingTheReviewClearsTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        let batch = try batchCard(vm)

        vm.saveDraft([batch.items[0].id: .delete], for: batch.id)
        vm.decideIndividually(Dictionary(uniqueKeysWithValues: batch.items.map { ($0.id, Decision.keep) }))

        #expect(vm.draft(for: batch.id).isEmpty)
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

@MainActor
struct SimilarReviewTests {
    private func similarCard(_ vm: FeedViewModel) throws -> SimilarGroup {
        guard case .similar(let group) = try #require(vm.currentCard) else {
            Issue.record("Expected a similar card on top")
            throw CancellationError()
        }
        try #require(group.others.count >= 2)
        return group
    }

    private func lockedMock(swipes: Int) -> FeedViewModel {
        FeedViewModel.mock(
            startingAt: .similar,
            entitlements: TestEntitlements(isUnlocked: false),
            allowance: SwipeAllowance(balance: swipes, tunables: .standard, now: .now)
        )
    }

    @Test func theReviewSetPutsTheBestPickFirstAndStartsOnTheTappedShot() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let tapped = group.others[1]

        let set = ReviewSet(group: group, startingAt: tapped.id)

        #expect(set.id == FeedCard.similar(group).id)
        #expect(set.title == "Similar shots")
        #expect(set.items.map(\.id) == [group.bestID] + group.others.map(\.id))
        #expect(set.items[set.start].id == tapped.id)
        #expect(set.bestID == group.bestID)
        #expect(set.reason == group.reason)
        #expect(set.visitOrder(draft: [:]).first?.id == tapped.id, "The deck opens on the tapped shot")
        #expect(set.visitOrder(draft: [:]).count == group.items.count)
    }

    @Test func reopeningResumesAfterTheDraftedShots() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let set = ReviewSet(group: group, startingAt: group.bestID)
        let draft = [group.bestID: Decision.keep]

        let order = set.visitOrder(draft: draft)

        #expect(order.first?.id == group.bestID, "Drafted shots come first so undo reaches them")
        #expect(order.dropFirst().map(\.id) == group.others.map(\.id))
    }

    @Test func aDraftIsKeptByCardID() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let draft = [group.bestID: Decision.keep]

        vm.saveDraft(draft, for: FeedCard.similar(group).id)

        #expect(vm.draft(for: group.id) == draft)
    }

    @Test func aBatchCardIDIsItsBatchID() throws {
        let vm = FeedViewModel.mock(startingAt: .batch)
        guard case .batch(let batch) = try #require(vm.currentCard) else { return }
        // Drafts saved before similar reviews existed are keyed by batch ID.
        #expect(FeedCard.batch(batch).id == batch.id)
    }

    @Test func decidingOneByOneAppliesTheReviewAndUnreachedShotsFollowTheirMarks() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let start = vm.index
        let group = try similarCard(vm)
        let deletedBest = group.best, keptOther = group.others[0], unreached = group.others[1]

        vm.decideIndividually([deletedBest.id: .delete, keptOther.id: .keep])

        #expect(vm.index == start + 1)
        #expect(vm.decisions[deletedBest.id] == .delete, "Deleting the best pick is the user's call")
        #expect(vm.decisions[keptOther.id] == .keep)
        #expect(vm.decisions[unreached.id] == .delete, "Unreached shots are still marked by default")
        #expect(vm.draft(for: group.id).isEmpty)
    }

    @Test func theCardFaceShowsTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let kept = group.others[0]

        vm.saveDraft([group.bestID: .delete, kept.id: .keep], for: group.id)

        let marked = vm.markedForClearing(in: group)
        #expect(marked.contains(group.bestID))
        #expect(!marked.contains(kept.id))
        #expect(marked.contains(group.others[1].id), "Shots the review didn't reach keep their mark")
        #expect(vm.swipeLabel(.left, for: .similar(group)) == "Clear \(group.items.count - 1)")
    }

    @Test func togglingAMarkUpdatesTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let shot = group.others[0], other = group.others[1]
        vm.saveDraft([shot.id: .delete], for: group.id)

        vm.toggleMark(shot.id, in: group)
        #expect(vm.draft(for: group.id)[shot.id] == .keep)
        #expect(!vm.markedForClearing(in: group).contains(shot.id))

        vm.toggleMark(other.id, in: group)
        #expect(vm.draft(for: group.id)[other.id] == .keep)
        vm.toggleMark(other.id, in: group)
        #expect(vm.draft(for: group.id)[other.id] == .delete)
        #expect(vm.markedForClearing(in: group).contains(other.id))
    }

    @Test func togglingWithoutADraftLeavesNoDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)

        vm.toggleMark(group.others[0].id, in: group)

        #expect(vm.draft(for: group.id).isEmpty)
    }

    @Test func swipingLeftAfterClosingEarlyCommitsTheDraft() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let kept = group.others[0]

        vm.saveDraft([group.bestID: .keep, kept.id: .keep], for: group.id)
        vm.decide(.left)

        #expect(vm.decisions[group.bestID] == .keep)
        #expect(vm.decisions[kept.id] == .keep)
        #expect(Set(vm.pendingItems.map(\.id)) == Set(group.others.dropFirst().map(\.id)))
    }

    @Test func aFinishedReviewCostsOneSwipeAndDraftsCostNone() throws {
        let vm = lockedMock(swipes: 5)
        let group = try similarCard(vm)

        vm.saveDraft([group.bestID: .keep], for: group.id)
        vm.toggleMark(group.others[0].id, in: group)
        #expect(vm.swipesLeft == 5)

        vm.decideIndividually(Dictionary(uniqueKeysWithValues: group.items.map { ($0.id, Decision.keep) }))

        #expect(vm.swipesLeft == 4)
    }

    @Test func outOfSwipesKeepsTheReviewAsADraftAndOpensTheWall() throws {
        let vm = lockedMock(swipes: 0)
        let start = vm.index
        let group = try similarCard(vm)
        let outcome = Dictionary(uniqueKeysWithValues: group.items.map { ($0.id, Decision.keep) })

        vm.decideIndividually(outcome)

        #expect(vm.index == start)
        #expect(vm.draft(for: group.id) == outcome)
        #expect(vm.isWallPresented)
    }

    @Test func undoBringsBackTheDraftAndMarks() throws {
        let vm = FeedViewModel.mock(startingAt: .similar)
        let group = try similarCard(vm)
        let draft = [group.others[0].id: Decision.keep]
        vm.saveDraft(draft, for: group.id)
        let marked = vm.markedForClearing(in: group)

        vm.decideIndividually(Dictionary(uniqueKeysWithValues: group.items.map { ($0.id, Decision.delete) }))
        vm.undo()

        #expect(vm.draft(for: group.id) == draft)
        #expect(vm.markedForClearing(in: group) == marked)
        #expect(vm.returningCard?.direction == .left)
    }
}

struct SessionCodingTests {
    @Test func sessionsRoundTripThroughJSON() throws {
        let session = MockFeedBuilder().makeSessionNow(number: 2, options: FeedOptions(skipFavorites: false))
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }
}
