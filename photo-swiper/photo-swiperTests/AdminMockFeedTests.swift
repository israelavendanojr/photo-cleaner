import Foundation
import Testing
@testable import photo_swiper

/// Admin Tools' mock cards in the live deck: queued on top, never charged, and in the pile without
/// ever being saved or reaching the library.
@MainActor
struct AdminMockFeedTests {
    private let store = SpyProgressStore()
    private let library = FakeLibrary()
    private let defaults = freshDefaults()

    /// A free user with a few swipes. The bin holds almost nothing unless `bin` says otherwise, so the
    /// pile limit shows up after one delete.
    private func launch(swipes: Int = 3, bin: Int64 = 1, unlocked: Bool = false) async -> FeedViewModel {
        let vm = FeedViewModel(
            library: library, builder: MockFeedBuilder(), store: store,
            entitlements: TestEntitlements(isUnlocked: unlocked), defaults: defaults,
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: swipes, tunables: .standard, now: .now)),
            freeTier: .fixed(FreeTierLimits(freeBinBytes: bin))
        )
        await vm.start()
        return vm
    }

    /// Fails if any mock id was written to the store or saved in the defaults.
    private func expectNothingMockSaved(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(store.writtenIDs.allSatisfy { !LibraryItem.isAdminMock(id: $0) }, "A mock id reached the store", sourceLocation: sourceLocation)
        #expect(store.pile().allSatisfy { !$0.isAdminMock }, sourceLocation: sourceLocation)
        let saved = defaults.dictionaryRepresentation().values.map { "\($0)" }
        #expect(saved.allSatisfy { !$0.contains(AdminMockCards.idPrefix) }, "A mock id reached the defaults", sourceLocation: sourceLocation)
    }

    private func bytes(_ items: [LibraryItem]) -> Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    private func mock(_ kind: AdminMockKind) -> FeedCard {
        var rng = SeededGenerator(seed: 3)
        return AdminMockCards.card(kind, using: &rng)
    }

    @Test func anAddedCardGoesOnTop() async throws {
        let vm = await launch()
        vm.decideCurrent(.right)
        let next = try #require(vm.currentCard)

        let card = mock(.similar)
        vm.admin.adminInsertMockCard(card)

        #expect(vm.currentCard == card)
        #expect(vm.nextCard == next, "The card that was on top comes right after")
        #expect(vm.adminQueuedMockCount == 1)
    }

    @Test func cardsQueueInTheOrderAdded() async throws {
        let vm = await launch()
        let real = try #require(vm.currentCard)
        let added = [mock(.similar), mock(.photo), mock(.screenshots)]

        for card in added { vm.admin.adminInsertMockCard(card) }

        #expect(Array(vm.cards[vm.index..<vm.index + 3]) == added, "First added, first up")
        #expect(vm.cards[vm.index + 3] == real, "The real card waits behind them")
        #expect(vm.adminQueuedMockCount == 3)
    }

    @Test func aMockCardOnTopStaysOnTopWhenAnotherIsQueued() async throws {
        let vm = await launch()
        let first = mock(.duplicates)
        vm.admin.adminInsertMockCard(first)
        let shown = try #require(vm.currentCard)

        vm.admin.adminInsertMockCard(mock(.video))

        #expect(vm.currentCard == shown, "The card being looked at doesn't change")
        #expect(shown == first)
    }

    @Test func theQueuedCountFollowsSwipesAndRemoval() async throws {
        let vm = await launch()
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.admin.adminInsertMockCard(mock(.photo))
        #expect(vm.adminQueuedMockCount == 2)

        vm.decideCurrent(.right)
        #expect(vm.adminQueuedMockCount == 1, "A swiped one is no longer queued")

        vm.admin.adminRemoveMockCards()
        #expect(vm.adminQueuedMockCount == 0)
    }

    @Test(arguments: AdminMockKind.allCases)
    func aDeletedMockCardGoesToThePileWithoutBeingSaved(_ kind: AdminMockKind) async throws {
        let vm = await launch(swipes: 1, bin: 100_000_000_000)
        let card = mock(kind)
        vm.admin.adminInsertMockCard(card)
        let swipesBefore = vm.allowance.remaining
        let deleted = vm.bytesToClear(for: card)

        vm.decideCurrent(.left)

        #expect(vm.currentCard != card, "Moved on")
        #expect(deleted > 0)
        #expect(vm.pendingBytes == deleted, "In the pile")
        #expect(vm.pendingItems.allSatisfy { $0.isAdminMock })
        #expect(vm.allowance.remaining == swipesBefore, "No swipe spent")
        #expect(store.decisions(for: Set(card.items.map(\.id))).isEmpty, "Nothing saved")
        expectNothingMockSaved()
    }

    @Test func aMockCardSwipesEvenWithNoSwipesLeft() async throws {
        let vm = await launch(swipes: 0)
        vm.admin.adminInsertMockCard(mock(.photo))

        vm.decideCurrent(.left)

        #expect(!vm.isWallPresented)
        #expect(vm.allowance.remaining == 0)
        #expect(vm.pendingItems.count == 1)
    }

    @Test func aOneByOneReviewOfAMockCardPilesWithoutSaving() async throws {
        let vm = await launch(swipes: 0, bin: 100_000_000_000)
        let card = mock(.screenshots)
        vm.admin.adminInsertMockCard(card)

        let outcome = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, Decision.delete) })
        #expect(vm.canDecideCurrentIndividually(outcome))
        vm.decideCurrentIndividually(outcome)

        #expect(vm.currentCard != card)
        #expect(Set(vm.pendingItems.map(\.id)) == Set(card.items.map(\.id)))
        expectNothingMockSaved()
    }

    @Test func undoTakesAMockCardBackOutOfThePile() async throws {
        let vm = await launch(bin: 100_000_000_000)
        let card = mock(.duplicates)
        vm.admin.adminInsertMockCard(card)
        vm.decideCurrent(.left)
        #expect(!vm.pendingItems.isEmpty)

        vm.undo()

        #expect(vm.currentCard == card)
        #expect(vm.pendingItems.isEmpty)
    }

    // MARK: The free pile limit

    @Test func mockItemsCountTowardTheFreePileLimit() async throws {
        let first = mock(.photo)
        let vm = await launch(bin: bytes(first.items) + 1)
        vm.admin.adminInsertMockCard(first)
        vm.decideCurrent(.left)

        #expect(vm.pileCountedBytes == bytes(first.items))
        vm.admin.adminInsertMockCard(mock(.video))
        #expect(!vm.canDecideCurrent(.left), "Over the limit, even for a mock card")
        #expect(vm.canDecideCurrent(.right), "Keeping still goes through")
    }

    @Test func aMockCardOverTheLimitIsRefusedWithThePileNoticeNotTheWall() async throws {
        let vm = await launch(swipes: 0)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        let second = mock(.photo)
        vm.admin.adminInsertMockCard(second)

        vm.decideCurrent(.left)
        #expect(vm.currentCard == second, "Refused whole")
        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented, "No swipes left, but a mock card never needs one")

        vm.dismissPileFullNotice()
        vm.refuse(.left, cardID: second.id)
        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented)
    }

    @Test func unlockedMockDeletesHaveNoLimit() async throws {
        let vm = await launch(unlocked: true)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.admin.adminInsertMockCard(mock(.photo))

        vm.decideCurrent(.left)
        #expect(vm.canDecideCurrent(.left))
        vm.decideCurrent(.left)
        #expect(vm.pendingItems.count == 2)
    }

    // MARK: Deleting from the pile

    @Test func deletingMockItemsNeverReachesTheLibrary() async throws {
        let vm = await launch(bin: 100_000_000_000)
        var asked: [LibraryItem] = []
        library.onDelete = { items in
            asked += items
            return DeletionOutcome(deleted: items.map(\.id))
        }
        vm.admin.adminInsertMockCard(mock(.similar))
        vm.decideCurrent(.left)
        let pile = vm.pendingItems

        let freed = await vm.deleteNow(pile)

        #expect(asked.isEmpty, "No mock item is ever passed to library.delete")
        #expect(freed == bytes(pile), "Their bytes count as freed")
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.freedBytes == 0, "The library's freed total is only real deletes")
        expectNothingMockSaved()
    }

    @Test func deletingMockItemsRunsThePostDeleteOffer() async throws {
        let vm = await launch(bin: 100_000_000_000)
        vm.admin.adminInsertMockCard(mock(.video))
        vm.decideCurrent(.left)
        let pile = vm.pendingItems

        #expect(await vm.deleteNow(pile) != nil)
        vm.releaseReviewPrompt()

        #expect(vm.isDeleteUpsellDue)
        #expect(vm.upsellFreedBytes == bytes(pile))
    }

    @Test func aMixedPileSendsOnlyRealItemsToTheLibrary() async throws {
        let vm = await launch(bin: 100_000_000_000)
        var asked: [LibraryItem] = []
        library.onDelete = { items in
            asked += items
            return DeletionOutcome(deleted: items.map(\.id))
        }
        vm.decideCurrent(.left)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        let pile = vm.pendingItems
        let real = pile.filter { !$0.isAdminMock }
        #expect(!real.isEmpty)
        #expect(pile.contains { $0.isAdminMock })

        let freed = await vm.deleteNow(pile)

        #expect(asked.map(\.id) == real.map(\.id))
        #expect(freed == bytes(pile))
        #expect(vm.pendingItems.isEmpty)
        expectNothingMockSaved()
    }

    @Test func cancellingTheSystemPromptKeepsTheMockItemsToo() async throws {
        let vm = await launch(bin: 100_000_000_000)
        library.onDelete = { _ in throw DeletionError.cancelled }
        vm.decideCurrent(.left)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        let pile = vm.pendingItems

        #expect(await vm.deleteNow(pile) == nil)
        #expect(vm.pendingItems.map(\.id) == pile.map(\.id))
    }

    @Test func deletingOnlyMockItemsIsNotCountedAndKeepsUndo() async throws {
        let vm = await launch(bin: 100_000_000_000)
        vm.decideCurrent(.right)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        #expect(vm.canUndo)

        #expect(await vm.deleteNow(vm.pendingItems) != nil)

        #expect(vm.canUndo, "No photo left the library, so the real swipes can still be undone")
        #expect(defaults.integer(forKey: DefaultsKey.deleteCount) == 0, "Not counted toward the review prompt")
    }

    @Test func mockOnlyDeletesNeverEarnAReviewPrompt() async throws {
        let vm = await launch(bin: 100_000_000_000, unlocked: true)
        vm.admin.adminInsertMockCard(mock(.video))
        vm.decideCurrent(.left)

        #expect(await vm.deleteNow(vm.pendingItems) != nil)
        vm.releaseReviewPrompt()

        #expect(!vm.isReviewPromptDue)
        #expect(!vm.isDeleteUpsellDue)
    }

    @Test func whenTheLibraryDeletesNoneOfTheRealItemsTheMocksStay() async throws {
        let vm = await launch(bin: 100_000_000_000)
        library.onDelete = { items in DeletionOutcome(undeletable: items.map(\.id)) }
        vm.decideCurrent(.left)
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        let mocks = vm.pendingItems.filter { $0.isAdminMock }

        #expect(await vm.deleteNow(vm.pendingItems) == nil)
        #expect(vm.pendingItems.map(\.id) == mocks.map(\.id), "The undeletable one leaves; the mocks stay")
        expectNothingMockSaved()
    }

    @Test func keepingMockItemsSavesNothing() async throws {
        let vm = await launch(bin: 100_000_000_000)
        vm.admin.adminInsertMockCard(mock(.screenshots))
        vm.decideCurrent(.left)

        vm.keep(vm.pendingItems)

        #expect(vm.pendingItems.isEmpty)
        expectNothingMockSaved()
    }

    @Test func removingMockCardsDropsOnlyTheOnesAhead() async throws {
        let vm = await launch()
        let swiped = mock(.photo)
        vm.admin.adminInsertMockCard(swiped)
        vm.decideCurrent(.right)
        let real = try #require(vm.currentCard)
        vm.admin.adminInsertMockCard(mock(.video))
        vm.admin.adminInsertMockCard(mock(.similar))

        vm.admin.adminRemoveMockCards()

        #expect(vm.currentCard == real)
        #expect(vm.cards.contains(swiped), "Already swiped, so it stays behind")
        #expect(vm.cards.filter(\.isAdminMock).count == 1)
    }

    @Test func removingMockCardsClearsThemFromThePile() async throws {
        let vm = await launch(bin: 100_000_000_000)
        vm.decideCurrent(.left)
        let real = vm.pendingItems
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.left)
        #expect(vm.pendingItems.count == real.count + 1)

        vm.admin.adminRemoveMockCards()
        #expect(vm.pendingItems.map(\.id) == real.map(\.id), "Only the real delete is left")

        vm.undo()
        #expect(vm.pendingItems.map(\.id) == real.map(\.id), "Undo doesn't bring the mock back into the pile")
    }

    @Test func aRelaunchLeavesMockCardsOut() async throws {
        let vm = await launch()
        vm.admin.adminInsertMockCard(mock(.photo))
        vm.decideCurrent(.right)
        vm.decideCurrent(.right)
        let real = try #require(vm.currentCard)
        vm.admin.adminInsertMockCard(mock(.similar))

        let relaunched = await launch()

        #expect(relaunched.currentCard == real, "Back on the same real card")
        #expect(relaunched.cards.allSatisfy { !$0.isAdminMock })
    }

    @Test func aRelaunchLeavesMockItemsOutOfThePile() async throws {
        let vm = await launch(bin: 100_000_000_000)
        vm.admin.adminInsertMockCard(mock(.similar))
        vm.decideCurrent(.left)
        #expect(!vm.pendingItems.isEmpty)

        let relaunched = await launch(bin: 100_000_000_000)

        #expect(relaunched.pendingItems.isEmpty)
        expectNothingMockSaved()
    }

    @Test func aMockCardLeavesCaughtUp() async throws {
        let vm = FeedViewModel(library: library, builder: EmptyBuilder(), store: store,
                               entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        #expect(vm.phase == .caughtUp)

        let card = mock(.similar)
        vm.admin.adminInsertMockCard(card)

        #expect(vm.phase == .feed)
        #expect(vm.currentCard == card)
    }
}

/// A library with nothing left to show.
private struct EmptyBuilder: FeedBuilding {
    func makeSession(number: Int, options: FeedOptions) async -> Session {
        Session(number: number, cards: [])
    }

    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? {
        nil
    }
}

/// The in-memory store, recording every item id a mutating call is given.
@MainActor
final class SpyProgressStore: ProgressStoring {
    private let base = InMemoryProgressStore()
    private(set) var writtenIDs: [LibraryItem.ID] = []

    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision] { base.decisions(for: ids) }
    func save(_ changes: [LibraryItem.ID: StoredDecision?]) {
        writtenIDs += changes.keys
        base.save(changes)
    }

    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        writtenIDs += ids
        base.settle(ids, as: settlement)
    }

    func goneIDs() -> Set<LibraryItem.ID> { base.goneIDs() }
    func reopen(_ ids: Set<LibraryItem.ID>) {
        writtenIDs += ids
        base.reopen(ids)
    }

    func pile() -> [LibraryItem] { base.pile() }
    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID> { base.excludedFromNewSession(asOf: now) }
    func reviewedCount() -> Int { base.reviewedCount() }
    func freedBytes() -> Int64 { base.freedBytes() }
    func lastSessionNumber() -> Int { base.lastSessionNumber() }
    func loadSession() -> SavedSession? { base.loadSession() }
    func saveSession(_ saved: SavedSession?) { base.saveSession(saved) }
    @discardableResult
    func commit(_ changes: [LibraryItem.ID: StoredDecision?], deck: DeckWrite) -> Bool {
        writtenIDs += changes.keys
        return base.commit(changes, deck: deck)
    }

    var skipFavorites: Bool {
        get { base.skipFavorites }
        set { base.skipFavorites = newValue }
    }

    func reset() { base.reset() }
}
