import Foundation
import Testing
@testable import photo_swiper

/// The free pile's limit of 50, and the unlock offered after a free user's delete.
@MainActor
struct PileCapTests {
    private let cap = FeedViewModel.freePileCap
    /// Enough free swipes that the allowance never gets in the way.
    private let tunables = SwipeAllowance.Tunables(cap: 1_000)
    private let defaults = freshDefaults()

    /// The mock deck on its first card, a photo, with `pile` items already waiting to be cleared.
    private func vm(pile: Int, unlocked: Bool = false, swipes: Int = 500) -> FeedViewModel {
        let store = InMemoryProgressStore()
        let items = (0..<pile).map { i in
            LibraryItem(id: "pile-\(i)", kind: .photo, date: .now, location: nil, bytes: 1_000_000, image: .bundled("photo-sunset"))
        }
        store.save(Dictionary(uniqueKeysWithValues: items.map { item -> (LibraryItem.ID, StoredDecision?) in
            (item.id, StoredDecision(decision: .delete, decidedAt: .now, sessionNumber: 0, item: item))
        }))
        let builder = MockFeedBuilder()
        return FeedViewModel(
            library: FakeLibrary(),
            builder: builder,
            store: store,
            entitlements: TestEntitlements(isUnlocked: unlocked),
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: 500, reviewedItems: 0, freedBytes: 0),
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: swipes, tunables: tunables, now: .now)),
            allowanceTunables: tunables
        )
    }

    /// Keeps cards until a batch is on top.
    private func keepUntilBatch(_ vm: FeedViewModel) throws -> ItemBatch {
        for _ in 0..<vm.cards.count {
            if case .batch(let batch) = try #require(vm.currentCard) { return batch }
            vm.decide(.right)
        }
        Issue.record("No batch card in the mock deck")
        throw CancellationError()
    }

    private func requirePhotoOnTop(_ vm: FeedViewModel) throws {
        guard case .photo = try #require(vm.currentCard) else {
            Issue.record("Expected a photo card on top")
            throw CancellationError()
        }
    }

    // MARK: The cap

    @Test func aFullPileRefusesAFreeUsersDelete() throws {
        let vm = vm(pile: cap)
        try requirePhotoOnTop(vm)
        let start = vm.index
        #expect(vm.isPileFull)
        #expect(!vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.index == start, "Nothing was committed")
        #expect(vm.pendingItems.count == cap)
        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented)
    }

    @Test func aRefusedDeleteRecordsNothingAndSpendsNoSwipe() throws {
        let vm = vm(pile: cap)
        let swipes = vm.swipesLeft

        vm.decide(.left)

        #expect(vm.swipesLeft == swipes)
        #expect(vm.decisions.isEmpty)
        #expect(!vm.canUndo)
        #expect(vm.deleteChip == nil)
    }

    @Test func theLastPlaceFillsThenTheNextDeleteIsRefused() throws {
        let vm = vm(pile: cap - 1)
        try requirePhotoOnTop(vm)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.count == cap)
        #expect(!vm.isPileFullNoticePresented)
        try requirePhotoOnTop(vm)
        #expect(!vm.canDecide(.left))
    }

    @Test func keepAndLaterStillGoThroughAtTheCap() throws {
        let vm = vm(pile: cap)
        let start = vm.index
        #expect(vm.canDecide(.right))
        #expect(vm.canDecide(.up))

        vm.decide(.right)
        vm.decide(.up)

        #expect(vm.index == start + 2)
        #expect(!vm.isPileFullNoticePresented)
        #expect(vm.pendingItems.count == cap)
    }

    @Test func unlockedHasNoCap() throws {
        let vm = vm(pile: cap, unlocked: true)
        #expect(vm.pileLimit == nil)
        #expect(!vm.isPileFull)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.count == cap + 1)
        #expect(!vm.isPileFullNoticePresented)
    }

    @Test func aBatchThatWouldOverflowIsRefusedWhole() throws {
        let probe = vm(pile: 0)
        let size = try keepUntilBatch(probe).items.count
        try #require(size > 1)

        let vm = vm(pile: cap - size + 1)
        let batch = try keepUntilBatch(vm)
        let start = vm.index
        #expect(!vm.canDecide(.left))
        #expect(vm.canDecide(.right))

        vm.decide(.left)

        #expect(vm.index == start)
        #expect(vm.pendingItems.count == cap - size + 1, "No partial add")
        #expect(!vm.pendingItems.contains { batch.items.map(\.id).contains($0.id) })
        #expect(vm.isPileFullNoticePresented)
    }

    @Test func aBatchThatExactlyFillsThePileGoesThrough() throws {
        let probe = vm(pile: 0)
        let size = try keepUntilBatch(probe).items.count

        let vm = vm(pile: cap - size)
        _ = try keepUntilBatch(vm)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.count == cap)
    }

    @Test func aDraftCountsTowardTheCap() throws {
        let vm = vm(pile: cap - 1)
        let batch = try keepUntilBatch(vm)
        // Only one drafted delete; the rest kept, so a left swipe adds just one.
        var draft = Dictionary(uniqueKeysWithValues: batch.items.map { ($0.id, Decision.keep) })
        draft[batch.items[0].id] = .delete
        vm.saveDraft(draft, for: batch.id)
        #expect(vm.canDecide(.left))

        draft[batch.items[1].id] = .delete
        vm.saveDraft(draft, for: batch.id)
        #expect(!vm.canDecide(.left))
        #expect(!vm.canDecide(.right), "Drafted deletes still clear on a right swipe")
    }

    @Test func aOneByOneReviewPastTheCapIsKeptAsADraft() throws {
        let vm = vm(pile: cap - 1)
        let batch = try keepUntilBatch(vm)
        let start = vm.index
        let swipes = vm.swipesLeft
        let outcome = Dictionary(uniqueKeysWithValues: batch.items.prefix(2).map { ($0.id, Decision.delete) })
        #expect(!vm.canDecideIndividually(outcome))

        vm.decideIndividually(outcome)

        #expect(vm.index == start)
        #expect(vm.swipesLeft == swipes)
        #expect(vm.draft(for: batch.id) == outcome)
        #expect(vm.pendingItems.count == cap - 1)
        #expect(vm.isPileFullNoticePresented)
    }

    @Test func aOneByOneReviewThatFitsGoesThrough() throws {
        let vm = vm(pile: cap - 1)
        let batch = try keepUntilBatch(vm)
        let outcome = [batch.items[0].id: Decision.delete]
        #expect(vm.canDecideIndividually(outcome))

        vm.decideIndividually(outcome)

        #expect(vm.pendingItems.count == cap)
    }

    // MARK: Refusing

    @Test func refusingWhenOutOfSwipesOpensTheWall() {
        let vm = vm(pile: cap, swipes: 0)
        #expect(!vm.canDecide(.right))

        vm.refuse(.right)

        #expect(vm.isWallPresented)
        #expect(!vm.isPileFullNoticePresented)
    }

    @Test func refusingWithAFullPileShowsTheNotice() {
        let vm = vm(pile: cap)

        vm.refuse(.left)

        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented)
    }

    @Test func deletingFromAFullPileMakesRoom() async throws {
        let vm = vm(pile: cap)
        #expect(!vm.canDecide(.left))

        await vm.deleteNow(Array(vm.pendingItems.prefix(1)))

        #expect(vm.canDecide(.left))
    }

    // MARK: The unlock offer after a delete

    /// A started deck with several deletes pending and one earlier delete on record, so a big
    /// delete would earn a review prompt if the user were unlocked.
    private func started(unlocked: Bool, library: FakeLibrary = FakeLibrary()) async throws -> (FeedViewModel, big: LibraryItem) {
        defaults.set(1, forKey: DefaultsKey.deleteCount)
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: unlocked), defaults: defaults)
        await vm.start()
        for _ in 0..<6 { vm.decide(.left) }
        let big = try #require(vm.pendingItems.first { $0.bytes >= ReviewPrompt.minimumFreedBytes })
        return (vm, big)
    }

    @Test func aFreeUsersDeleteOffersTheUnlockOnceThePileCloses() async throws {
        let (vm, big) = try await started(unlocked: false)

        await vm.deleteNow([big])
        #expect(!vm.isDeleteUpsellDue, "Not while the freed confirmation shows")
        vm.releaseReviewPrompt()

        #expect(vm.isDeleteUpsellDue)
        #expect(vm.upsellFreedBytes == big.bytes)
        #expect(!vm.isReviewPromptDue, "The offer replaces the review prompt")

        vm.finishDeleteUpsell()
        #expect(!vm.isDeleteUpsellDue)
        #expect(defaults.integer(forKey: DefaultsKey.deleteCount) == 2, "The delete still counts")
    }

    @Test func unlockedDeletesNeverOfferTheUnlock() async throws {
        let (vm, big) = try await started(unlocked: true)

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isDeleteUpsellDue)
        #expect(vm.isReviewPromptDue, "Unlocked users get the review prompt as before")
    }

    @Test func noOfferWhileTheWallIsUp() async throws {
        let (vm, big) = try await started(unlocked: false)
        vm.presentWall()

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isDeleteUpsellDue)
        #expect(!vm.isReviewPromptDue)
    }

    @Test func aCancelledDeleteOffersNothing() async throws {
        let library = FakeLibrary()
        library.onDelete = { _ in throw DeletionError.cancelled }
        let (vm, big) = try await started(unlocked: false, library: library)

        await vm.deleteNow([big])
        vm.releaseReviewPrompt()

        #expect(!vm.isDeleteUpsellDue)
    }
}
