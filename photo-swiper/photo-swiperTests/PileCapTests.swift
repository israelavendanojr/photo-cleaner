import Foundation
import Testing
@testable import photo_swiper

/// The free pile's storage limit, and the unlock offered after a free user's delete.
@MainActor
struct PileCapTests {
    /// A small limit, so a few mock photos fill it.
    private let limit: Int64 = 100_000_000
    /// Enough free swipes that the allowance never gets in the way.
    private let tunables = SwipeAllowance.Tunables(cap: 1_000)
    private let defaults = freshDefaults()

    /// The mock deck on its first card, a photo, with `pile` (one item of that size, or these items)
    /// already waiting to be cleared.
    private func vm(
        pile: Int64 = 0,
        items: [LibraryItem]? = nil,
        limit: Int64? = nil,
        unlocked: Bool = false,
        swipes: Int = 500
    ) -> FeedViewModel {
        let store = InMemoryProgressStore()
        let items = items ?? (pile > 0 ? [item("pile-0", bytes: pile)] : [])
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
            freeTier: .fixed(FreeTierLimits(allowance: tunables, freeBinBytes: limit ?? self.limit))
        )
    }

    private func item(_ id: String, bytes: Int64) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: bytes, image: .bundled("photo-sunset"))
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

    /// The photo on top, which the deck starts with.
    @discardableResult
    private func requirePhotoOnTop(_ vm: FeedViewModel) throws -> LibraryItem {
        guard case .photo(let photo) = try #require(vm.currentCard) else {
            Issue.record("Expected a photo card on top")
            throw CancellationError()
        }
        return photo
    }

    private func bytes(_ items: [LibraryItem]) -> Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    /// The first card's size, from a fresh deck (the mock deck is the same every time).
    private func firstPhotoBytes() throws -> Int64 {
        try requirePhotoOnTop(vm()).bytes
    }

    private func batchBytes() throws -> (size: Int, bytes: Int64) {
        let batch = try keepUntilBatch(vm())
        return (batch.items.count, bytes(batch.items))
    }

    // MARK: The limit

    @Test func theDefaultFreeBinIsOneGigabyte() {
        #expect(FreeTierLimits.standard.freeBinBytes == 1_000_000_000)
        #expect(Format.limit(FreeTierLimits.standard.freeBinBytes) == "1 GB")
        #expect(Format.limit(1_500_000_000) == "1.5 GB")
        #expect(Format.limit(500_000_000) == "500 MB")
    }

    @Test func aFullPileRefusesAFreeUsersDelete() throws {
        let vm = vm(pile: limit)
        try requirePhotoOnTop(vm)
        let start = vm.index
        #expect(vm.isPileFull)
        #expect(vm.pileLimitBytes == limit)
        #expect(!vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.index == start, "Nothing was committed")
        #expect(vm.pendingItems.count == 1)
        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented)
    }

    @Test func aRefusedDeleteRecordsNothingAndSpendsNoSwipe() throws {
        let vm = vm(pile: limit)
        let swipes = vm.swipesLeft

        vm.decide(.left)

        #expect(vm.swipesLeft == swipes)
        #expect(vm.decisions.isEmpty)
        #expect(!vm.canUndo)
        #expect(vm.deleteChip == nil)
    }

    @Test func aDeleteThatJustFitsFillsThePileThenTheNextIsRefused() throws {
        let vm = vm(pile: limit - (try firstPhotoBytes()))
        try requirePhotoOnTop(vm)
        #expect(!vm.isPileFull)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pileCountedBytes == limit)
        #expect(vm.isPileFull)
        #expect(!vm.isPileFullNoticePresented)
        try requirePhotoOnTop(vm)
        #expect(!vm.canDecide(.left))
    }

    @Test func aDeleteOneByteTooBigIsRefused() throws {
        let vm = vm(pile: limit - (try firstPhotoBytes()) + 1)
        #expect(!vm.isPileFull, "Not full, but the photo doesn't fit")
        #expect(!vm.canDecide(.left))
    }

    @Test func keepAndLaterStillGoThroughAtTheLimit() throws {
        let vm = vm(pile: limit)
        let start = vm.index
        #expect(vm.canDecide(.right))
        #expect(vm.canDecide(.up))

        vm.decide(.right)
        vm.decide(.up)

        #expect(vm.index == start + 2)
        #expect(!vm.isPileFullNoticePresented)
        #expect(vm.pendingItems.count == 1)
    }

    @Test func unlockedHasNoLimit() throws {
        let vm = vm(pile: limit * 5, unlocked: true)
        #expect(vm.pileLimitBytes == nil)
        #expect(!vm.isPileFull)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.count == 2)
        #expect(!vm.isPileFullNoticePresented)
    }

    // MARK: Bigger than the limit

    @Test func anItemBiggerThanTheWholeLimitGoesIntoAnEmptyPile() throws {
        let vm = vm(limit: 1_000_000)
        let photo = try requirePhotoOnTop(vm)
        try #require(photo.bytes > 1_000_000)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.map(\.id) == [photo.id])
        #expect(vm.isPileFull)
        #expect(!vm.canDecide(.left), "Nothing more until it's cleared")
    }

    @Test func anItemBiggerThanTheLimitIsRefusedOnceThePileHasAnything() throws {
        let vm = vm(pile: 1, limit: 1_000_000)
        #expect(!vm.isPileFull)
        #expect(!vm.canDecide(.left))
    }

    @Test func aGroupBiggerThanTheLimitGoesWholeIntoAnEmptyPile() throws {
        let vm = vm(limit: 1_000_000)
        let batch = try keepUntilBatch(vm)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(Set(vm.pendingItems.map(\.id)) == Set(batch.items.map(\.id)))
    }

    // MARK: Unknown sizes

    @Test func unknownSizesCountAsATypicalPhoto() {
        let unknown = (0..<3).map { item("unknown-\($0)", bytes: 0) }
        let vm = vm(items: unknown + [item("known", bytes: 1_000_000)], limit: 10_000_000)

        #expect(vm.pendingBytes == 1_000_000, "What's shown stays the real size")
        #expect(vm.pileCountedBytes == 3 * FeedViewModel.unknownSizeBytes + 1_000_000)
        #expect(vm.isPileFull)
        #expect(!vm.canDecide(.left))
    }

    @Test func countedBytesOnlyReplacesZeroSizes() {
        #expect(FeedViewModel.unknownSizeBytes == 3_000_000)
        #expect(FeedViewModel.countedBytes([item("a", bytes: 5), item("b", bytes: 0)]) == 5 + 3_000_000)
        #expect(FeedViewModel.countedBytes([]) == 0)
    }

    // MARK: Groups

    @Test func aBatchThatWouldOverflowIsRefusedWhole() throws {
        let (size, batchBytes) = try batchBytes()
        try #require(size > 1)

        let vm = vm(pile: limit - batchBytes + 1)
        let batch = try keepUntilBatch(vm)
        let start = vm.index
        #expect(!vm.canDecide(.left))
        #expect(vm.canDecide(.right))

        vm.decide(.left)

        #expect(vm.index == start)
        #expect(vm.pendingItems.count == 1, "No partial add")
        #expect(!vm.pendingItems.contains { batch.items.map(\.id).contains($0.id) })
        #expect(vm.isPileFullNoticePresented)
    }

    @Test func aBatchThatExactlyFillsThePileGoesThrough() throws {
        let (size, batchBytes) = try batchBytes()

        let vm = vm(pile: limit - batchBytes)
        _ = try keepUntilBatch(vm)
        #expect(vm.canDecide(.left))

        vm.decide(.left)

        #expect(vm.pendingItems.count == 1 + size)
        #expect(vm.pileCountedBytes == limit)
    }

    @Test func aDraftCountsTowardTheLimit() throws {
        let probe = try keepUntilBatch(vm())
        let vm = vm(pile: limit - probe.items[0].bytes)
        let batch = try keepUntilBatch(vm)
        // Only one drafted delete; the rest kept, so a left swipe adds just that one.
        var draft = Dictionary(uniqueKeysWithValues: batch.items.map { ($0.id, Decision.keep) })
        draft[batch.items[0].id] = .delete
        vm.saveDraft(draft, for: batch.id)
        #expect(vm.canDecide(.left))

        draft[batch.items[1].id] = .delete
        vm.saveDraft(draft, for: batch.id)
        #expect(!vm.canDecide(.left))
        #expect(!vm.canDecide(.right), "Drafted deletes still clear on a right swipe")
    }

    @Test func aOneByOneReviewPastTheLimitIsKeptAsADraft() throws {
        let probe = try keepUntilBatch(vm())
        let vm = vm(pile: limit - probe.items[0].bytes)
        let batch = try keepUntilBatch(vm)
        let start = vm.index
        let swipes = vm.swipesLeft
        let outcome = Dictionary(uniqueKeysWithValues: batch.items.prefix(2).map { ($0.id, Decision.delete) })
        #expect(!vm.canDecideIndividually(outcome))

        vm.decideIndividually(outcome)

        #expect(vm.index == start)
        #expect(vm.swipesLeft == swipes)
        #expect(vm.draft(for: batch.id) == outcome)
        #expect(vm.pendingItems.count == 1)
        #expect(vm.isPileFullNoticePresented)
    }

    @Test func aOneByOneReviewThatFitsGoesThrough() throws {
        let probe = try keepUntilBatch(vm())
        let vm = vm(pile: limit - probe.items[0].bytes)
        let batch = try keepUntilBatch(vm)
        let outcome = [batch.items[0].id: Decision.delete]
        #expect(vm.canDecideIndividually(outcome))

        vm.decideIndividually(outcome)

        #expect(vm.pileCountedBytes == limit)
    }

    // MARK: Refusing

    @Test func refusingWhenOutOfSwipesOpensTheWall() {
        let vm = vm(pile: limit, swipes: 0)
        #expect(!vm.canDecide(.right))

        vm.refuse(.right)

        #expect(vm.isWallPresented)
        #expect(!vm.isPileFullNoticePresented)
    }

    @Test func refusingWithAFullPileShowsTheNotice() {
        let vm = vm(pile: limit)

        vm.refuse(.left)

        #expect(vm.isPileFullNoticePresented)
        #expect(!vm.isWallPresented)
    }

    @Test func deletingFromAFullPileMakesRoom() async throws {
        let vm = vm(pile: limit)
        #expect(!vm.canDecide(.left))

        await vm.deleteNow(Array(vm.pendingItems.prefix(1)))

        #expect(vm.canDecide(.left))
    }

    // MARK: Live limits

    @Test func theLimitFollowsTheFreeTierTunables() throws {
        let devMode = DevMode(environment: .testFlight, defaults: freshDefaults())
        devMode.setEnabled(true)
        let tier = FreeTierTunables(defaults: freshDefaults(), devMode: devMode)
        let builder = MockFeedBuilder()
        let vm = FeedViewModel(
            library: FakeLibrary(), builder: builder, entitlements: TestEntitlements(isUnlocked: false),
            session: builder.makeSessionNow(number: 1),
            stats: LibraryStats(totalItems: 500, reviewedItems: 0, freedBytes: 0), freeTier: tier
        )
        #expect(vm.pileLimitBytes == 1_000_000_000)

        tier.set(.freeBinMB, 250)
        #expect(vm.pileLimitBytes == 250_000_000)

        devMode.setEnabled(false)
        #expect(vm.pileLimitBytes == 1_000_000_000, "Developer mode off uses the defaults")
    }

    // MARK: The unlock offer after a delete

    /// A started deck with several deletes pending and one earlier delete on record, so a big
    /// delete would earn a review prompt if the user were unlocked.
    private func started(unlocked: Bool, library: FakeLibrary = FakeLibrary(), clock: TestClock = TestClock()) async throws -> (FeedViewModel, big: LibraryItem) {
        defaults.set(1, forKey: DefaultsKey.deleteCount)
        // A bin big enough for the mock deck's 1.2 GB video, which is the big delete here.
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: unlocked), defaults: defaults,
                               freeTier: .fixed(FreeTierLimits(freeBinBytes: 10_000_000_000)), now: { clock.now })
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

        vm.finishDeleteUpsell(shown: true)
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

    // MARK: How often the offer comes back

    /// Deletes one pending item and lets the pile close. True if the offer came due.
    private func deleteOne(_ vm: FeedViewModel) async throws -> Bool {
        let item = try #require(vm.pendingItems.first)
        await vm.deleteNow([item])
        vm.releaseReviewPrompt()
        return vm.isDeleteUpsellDue
    }

    @Test func theOfferWaitsADayAfterShowing() async throws {
        let clock = TestClock()
        let (vm, _) = try await started(unlocked: false, clock: clock)

        #expect(try await deleteOne(vm), "The first delete offers it")
        vm.finishDeleteUpsell(shown: true)

        clock.advance(hours: 23)
        #expect(try await deleteOne(vm) == false, "Not again within the day")
        #expect(!vm.isReviewPromptDue, "Free users still get no review prompt")

        clock.advance(hours: 1)
        #expect(try await deleteOne(vm), "Due again a full interval later")
    }

    @Test func theWaitFollowsTheFreeTierTunables() async throws {
        defaults.set(1, forKey: DefaultsKey.deleteCount)
        let clock = TestClock()
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false), defaults: defaults,
                               freeTier: .fixed(FreeTierLimits(freeBinBytes: 10_000_000_000, postDeleteUpsellInterval: 2 * 3600)),
                               now: { clock.now })
        await vm.start()
        for _ in 0..<6 { vm.decide(.left) }

        #expect(try await deleteOne(vm), "The first delete offers it")
        vm.finishDeleteUpsell(shown: true)

        clock.advance(hours: 1)
        #expect(try await deleteOne(vm) == false, "Not within the tuned 2 hours")

        clock.advance(hours: 1)
        #expect(try await deleteOne(vm), "Due again after the tuned interval")
    }

    @Test func anOfferNotShownDoesNotStartTheWait() async throws {
        let clock = TestClock()
        let (vm, _) = try await started(unlocked: false, clock: clock)

        #expect(try await deleteOne(vm))
        vm.finishDeleteUpsell(shown: false)
        #expect(defaults.object(forKey: DefaultsKey.deleteUpsellShownAt) == nil)

        #expect(try await deleteOne(vm), "Still due, since it never showed")
    }

    @Test func theLastShownDateIsRemembered() async throws {
        let clock = TestClock()
        defaults.set(clock.now.addingTimeInterval(-3600), forKey: DefaultsKey.deleteUpsellShownAt)
        let (vm, _) = try await started(unlocked: false, clock: clock)

        #expect(try await deleteOne(vm) == false, "Shown an hour ago, in an earlier launch")
        clock.advance(hours: 23)
        #expect(try await deleteOne(vm))
    }

    @Test func noOfferForTheRestOfTheSessionOnceTheWallHasShown() async throws {
        let clock = TestClock()
        let (vm, _) = try await started(unlocked: false, clock: clock)
        vm.presentWall()
        vm.dismissWall()

        #expect(try await deleteOne(vm) == false, "Not right after the wall")
        clock.advance(hours: 48)
        #expect(try await deleteOne(vm) == false, "Not for the rest of the session")
    }
}
