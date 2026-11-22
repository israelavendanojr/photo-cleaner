import Foundation
import Testing
@testable import photo_swiper

/// Deals one fixed deck, then nothing, so paging never changes what's on the table.
private final class LockedDeckBuilder: FeedBuilding, @unchecked Sendable {
    private let cards: [FeedCard]
    private var dealt = false

    init(_ cards: [FeedCard]) {
        self.cards = cards
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        defer { dealt = true }
        return Session(number: number, cards: dealt ? [] : cards)
    }
}

/// A locked feature (JUN-87) can be seen and tried, but committing it opens the paywall and is a no-op
/// for the model: nothing decided, no swipe charged, no undo step, the deck where it was, nothing saved.
@MainActor
struct LockedFeatureTests {
    private let tunables = SwipeAllowance.Tunables(cap: 20, refillAmount: 10, refillInterval: 6 * 3600)
    private let clock = TestClock()

    private func item(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: 1_000_000, image: .bundled("photo-sunset"))
    }

    private var photo: FeedCard { .photo(item("A")) }
    private var similar: FeedCard {
        .similar(SimilarGroup(id: "S", items: [item("S1"), item("S2"), item("S3")], bestID: "S1", reason: "Sharpest of the set"))
    }

    private var duplicates: FeedCard {
        .duplicates(DuplicateGroup(id: "D", items: [item("D1"), item("D2")], keepID: "D1", reason: "Highest resolution"))
    }

    private var batch: FeedCard {
        .batch(ItemBatch(id: "X", kind: .screenshots, label: "Screenshots", title: "2 screenshots", items: [item("X1"), item("X2")]))
    }

    private var video: LibraryItem {
        LibraryItem(id: "V", kind: .video(duration: 100), date: .now, location: nil, bytes: 400_000_000, image: .bundled("photo-sunset"))
    }

    private var videoCard: FeedCard { .video(video) }

    /// The ID a photo gets as a card of its own.
    private func single(_ id: LibraryItem.ID) -> FeedCard.ID { FeedCard.photo(item(id)).id }

    private static let lockedForFree = PlanAccess(free: .locked, paid: .unlocked)

    /// Every bundle, the trimmer and compression locked on the free plan.
    private func started(
        _ cards: [FeedCard],
        locked: [TierFeature] = [.similarShots, .duplicates, .screenshotBatches, .videoTrimmer, .videoCompression],
        entitlements: TestEntitlements = TestEntitlements(isUnlocked: false),
        store: InMemoryProgressStore = InMemoryProgressStore(),
        balance: Int = 5,
        freeBinBytes: Int64 = 1_000_000_000
    ) async -> FeedViewModel {
        let features = FeatureAvailabilityTunables.fixed(Dictionary(uniqueKeysWithValues: locked.map { ($0, Self.lockedForFree) }))
        let vm = FeedViewModel(
            library: FakeLibrary(),
            builder: LockedDeckBuilder(cards),
            store: store,
            entitlements: entitlements,
            defaults: freshDefaults(),
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: balance, tunables: tunables, now: clock.now)),
            freeTier: .fixed(FreeTierLimits(allowance: tunables, freeBinBytes: freeBinBytes)),
            features: features,
            now: { [clock] in clock.now }
        )
        await vm.start()
        await vm.waitForPage()
        return vm
    }

    private func allIDs(_ cards: [FeedCard]) -> Set<LibraryItem.ID> {
        Set(cards.flatMap { $0.items.map(\.id) })
    }

    // MARK: Swipes

    @Test(arguments: [TierFeature.similarShots, .duplicates, .screenshotBatches], [SwipeDirection.left, .right, .up])
    func swipingALockedBundleOpensThePaywallAndRecordsNothing(_ feature: TierFeature, _ direction: SwipeDirection) async throws {
        let card = try #require([similar, duplicates, batch].first { $0.feature == feature })
        let store = InMemoryProgressStore()
        let vm = await started([card, photo], store: store)
        let swipesBefore = vm.swipesLeft
        #expect(vm.currentCard?.id == card.id, "Dealt whole, not as its photos")

        #expect(!vm.canDecide(direction, cardID: card.id), "The deck springs it back")
        vm.refuse(direction, cardID: card.id)
        #expect(vm.lockedPrompt == LockedPrompt(feature: feature, cardID: card.id))
        #expect(!vm.isWallPresented, "The paywall, not the swipe wall")

        vm.decide(direction, cardID: card.id)
        #expect(vm.decisions.isEmpty)
        #expect(vm.swipesLeft == swipesBefore, "No swipe charged")
        #expect(vm.index == 0)
        #expect(!vm.canUndo)
        #expect(store.decisions(for: allIDs([card, photo])).isEmpty, "Nothing written")
    }

    @Test func aFinishedReviewOfALockedBundleIsKeptAsADraft() async throws {
        let store = InMemoryProgressStore()
        let vm = await started([similar, photo], store: store)
        let swipesBefore = vm.swipesLeft
        let outcome: [LibraryItem.ID: Decision] = ["S1": .keep, "S2": .delete, "S3": .delete]

        #expect(!vm.canDecideIndividually(outcome, cardID: "S"))
        vm.decideIndividually(outcome, cardID: "S")

        #expect(vm.decisions.isEmpty)
        #expect(vm.draft(for: "S") == outcome, "The review isn't lost")
        #expect(vm.swipesLeft == swipesBefore)
        #expect(vm.index == 0)
        #expect(!vm.canUndo)
        #expect(store.decisions(for: allIDs([similar])).isEmpty)
    }

    @Test func anUnlockedBundleSwipesAsBefore() async throws {
        let vm = await started([similar, photo], locked: [])
        #expect(vm.canDecide(.left, cardID: "S"))
        vm.decide(.left, cardID: "S")
        #expect(!vm.decisions.isEmpty)
        #expect(vm.currentCard?.id == photo.id)
    }

    // MARK: Closing the paywall (D1)

    @Test func closingThePaywallWithoutBuyingDealsTheCardAsItsPhotos() async throws {
        let store = InMemoryProgressStore()
        let vm = await started([similar, photo], store: store)
        let swipesBefore = vm.swipesLeft
        vm.saveDraft(["S2": .delete], for: "S")
        vm.refuse(.left, cardID: "S")

        vm.lockedPromptDismissed()

        #expect(vm.lockedPrompt == nil)
        #expect(vm.cards.map(\.id) == ["S1", "S2", "S3"].map(single) + [photo.id], "Same photos, same order, one card each")
        #expect(vm.currentCard?.id == single("S1"))
        #expect(vm.draft(for: "S").isEmpty, "Its partial review goes with it")
        #expect(vm.decisions.isEmpty)
        #expect(vm.swipesLeft == swipesBefore)
        #expect(!vm.canUndo)
        #expect(store.decisions(for: allIDs([similar, photo])).isEmpty)

        let saved = try #require(store.loadSession(), "The new deck is saved")
        #expect(saved.session.cards.map(\.id) == ["S1", "S2", "S3"].map(single) + [photo.id])
        #expect(saved.index == 0)
        #expect(saved.drafts["S"] == nil)

        vm.decide(.left, cardID: "S")
        #expect(vm.decisions.isEmpty, "The old bundle's ID decides nothing")
        vm.decide(.left, cardID: single("S1"))
        #expect(vm.decisions == ["S1": .delete])
    }

    @Test func undoStillReachesTheCardBeforeAnUnbundledOne() async throws {
        let vm = await started([photo, similar])
        let swipesBefore = vm.swipesLeft
        vm.decide(.right, cardID: photo.id)
        vm.refuse(.left, cardID: "S")
        vm.lockedPromptDismissed()
        #expect(vm.currentCard?.id == single("S1"))

        vm.undo()
        #expect(vm.currentCard?.id == photo.id)
        #expect(vm.cards.map(\.id) == [photo.id] + ["S1", "S2", "S3"].map(single))
        #expect(vm.decisions.isEmpty)
        #expect(vm.swipesLeft == swipesBefore, "The swipe is refunded")
    }

    @Test func aLockedBundleOutOfSwipesStillGetsThePaywallNotTheWall() async throws {
        let vm = await started([similar, photo], balance: 0)
        #expect(!vm.canDecide(.left, cardID: "S"))
        vm.refuse(.left, cardID: "S")
        #expect(vm.lockedPrompt == LockedPrompt(feature: .similarShots, cardID: "S"))
        #expect(!vm.isWallPresented)
        #expect(vm.swipesLeft == 0)
    }

    @Test func aLockedBundleWithAFullPileStillGetsThePaywallNotTheNotice() async throws {
        let vm = await started([similar, photo], freeBinBytes: 1)
        vm.refuse(.left, cardID: "S")
        #expect(vm.lockedPrompt != nil)
        #expect(!vm.isPileFullNoticePresented)
    }

    @Test func buyingKeepsTheBundleAndItSwipes() async throws {
        let entitlements = TestEntitlements(isUnlocked: false)
        let vm = await started([similar, photo], entitlements: entitlements)
        vm.refuse(.right, cardID: "S")

        entitlements.isUnlocked = true
        vm.lockedPromptDismissed()

        #expect(vm.currentCard?.id == "S", "Still a bundle")
        #expect(vm.canDecide(.right, cardID: "S"))
        vm.decide(.right, cardID: "S")
        #expect(vm.currentCard?.id == photo.id)
    }

    @Test func aPromptThatIsntForACardChangesNoCards() async throws {
        let vm = await started([similar, photo], locked: [.similarShots, .feedFilters])
        vm.requestUnlock(.feedFilters)
        #expect(vm.lockedPrompt == LockedPrompt(feature: .feedFilters, cardID: nil))

        vm.lockedPromptDismissed()
        #expect(vm.cards.map(\.id) == ["S", photo.id])
    }

    @Test func anUnlockedFeatureNeverAsksToUnlock() async throws {
        let vm = await started([photo], locked: [])
        vm.requestUnlock(.feedFilters)
        #expect(vm.lockedPrompt == nil)
    }

    @Test func aRefusalForACardNotOnTopOpensNothing() async throws {
        let vm = await started([photo, similar])
        vm.refuse(.left, cardID: "S")
        #expect(vm.lockedPrompt == nil)
        vm.lockedPromptDismissed()
        #expect(vm.cards.map(\.id) == [photo.id, "S"])
    }

    // MARK: Video edits

    @Test func aLockedTrimOrCompressionRecordsNothing() async throws {
        let store = InMemoryProgressStore()
        let vm = await started([videoCard, photo], store: store)
        let swipesBefore = vm.swipesLeft

        vm.decideEdit(PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100), cardID: videoCard.id)
        vm.decideEdit(PendingEdit(originalDuration: 100, compression: .balanced, compressedBytes: 80_000_000), cardID: videoCard.id)

        #expect(vm.decisions.isEmpty)
        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.swipesLeft == swipesBefore)
        #expect(vm.currentCard?.id == videoCard.id)
        #expect(!vm.canUndo)
        #expect(store.decisions(for: ["V"]).isEmpty)
    }

    @Test func theViewerAsksToUnlockOnlyForTheLockedPartOfAnEdit() {
        let trim = PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100)
        let compress = PendingEdit(originalDuration: 100, compression: .balanced, compressedBytes: 80_000_000)
        let trimLocked = VideoEditOptions(trimLocked: true)
        #expect(trimLocked.needsUnlock(trim))
        #expect(!trimLocked.needsUnlock(compress))
        #expect(!trimLocked.needsUnlock(level: .max))
        #expect(!trimLocked.needsUnlock(nil))

        let compressLocked = VideoEditOptions(compressLocked: true)
        #expect(compressLocked.needsUnlock(compress))
        #expect(compressLocked.needsUnlock(level: .light))
        #expect(!compressLocked.needsUnlock(level: nil), "Choosing no compression is always fine")
        #expect(!compressLocked.needsUnlock(trim))
        #expect(!VideoEditOptions().needsUnlock(trim))
    }

    @Test func onlyTheLockedPartOfAnEditIsHeldBack() async throws {
        let vm = await started([videoCard, photo], locked: [.videoTrimmer])
        #expect(vm.videoEditOptions.trimLocked && !vm.videoEditOptions.compressLocked)
        #expect(vm.videoEditOptions.canTrim, "Locked still shows the handles")

        vm.decideEdit(PendingEdit(originalDuration: 100, compression: .balanced, compressedBytes: 80_000_000), cardID: videoCard.id)
        #expect(vm.decisions == ["V": .keep], "Compression isn't locked, so it's queued")
    }
}
