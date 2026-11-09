import Foundation
import Testing
@testable import photo_swiper

/// Deals one fixed deck, then nothing, so paging never changes what's on the table.
private final class FixedDeckBuilder: FeedBuilding, @unchecked Sendable {
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

/// A swipe or review applies to the card the user acted on, even when a refill reorders the deck
/// underneath it (JUN-22, S-1).
@MainActor
struct CardIdentityTests {
    private let tunables = SwipeAllowance.Tunables(cap: 20, refillAmount: 10, refillInterval: 6 * 3600)

    private func item(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: 1_000_000, image: .bundled("photo-sunset"))
    }

    private var photoA: LibraryItem { item("A") }
    private var photoB: LibraryItem { item("B") }
    private var similar: SimilarGroup {
        SimilarGroup(id: "S", items: [item("S1"), item("S2"), item("S3")], bestID: "S1", reason: "Sharpest of the set")
    }
    private var batch: ItemBatch {
        ItemBatch(id: "X", kind: .screenshots, label: "Screenshots", title: "2 screenshots", items: [item("X1"), item("X2")])
    }

    /// A free user with swipes below the cap, so a refill is owed once `clock` moves on by an interval.
    private func started(_ cards: [FeedCard], clock: TestClock, store: any ProgressStoring = InMemoryProgressStore()) async -> FeedViewModel {
        let vm = FeedViewModel(
            library: FakeLibrary(),
            builder: FixedDeckBuilder(cards),
            store: store,
            entitlements: TestEntitlements(isUnlocked: false),
            defaults: freshDefaults(),
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: 5, tunables: tunables, now: clock.now)),
            freeTier: .fixed(FreeTierLimits(allowance: tunables)),
            now: { clock.now }
        )
        await vm.start()
        await vm.waitForPage()
        return vm
    }

    private func pendingIDs(_ vm: FeedViewModel) -> Set<LibraryItem.ID> {
        Set(vm.pendingItems.map(\.id))
    }

    @Test func aRefillBeforeTheSwipeDoesNotRedirectIt() async throws {
        let clock = TestClock()
        let vm = await started([.photo(photoA), .photo(photoB), .similar(similar)], clock: clock)
        #expect(vm.currentCard?.id == FeedCard.photo(photoA).id)

        clock.advance(hours: 6)
        vm.refreshAllowance()
        vm.decide(.left, cardID: FeedCard.photo(photoA).id)

        #expect(pendingIDs(vm) == ["A"])
        #expect(vm.decisions["S2"] == nil && vm.decisions["S3"] == nil, "The similar set stays undecided")
        #expect(vm.cards[vm.index - 1].id == FeedCard.photo(photoA).id, "Undo would bring A back")
    }

    @Test func aRefillLandingInsideTheSwipeDoesNotRedirectIt() async throws {
        let clock = TestClock()
        let vm = await started([.photo(photoA), .photo(photoB), .similar(similar)], clock: clock)

        clock.advance(hours: 6)
        vm.decide(.left, cardID: FeedCard.photo(photoA).id)

        #expect(pendingIDs(vm) == ["A"])
        #expect(vm.decisions["S2"] == nil && vm.decisions["S3"] == nil)
        #expect(vm.cards[vm.index - 1].id == FeedCard.photo(photoA).id, "A sits just behind the current card, where undo looks")
    }

    @Test func aFinishedReviewAppliesToTheReviewedBatch() async throws {
        let clock = TestClock()
        let vm = await started([.batch(batch), .photo(photoB), .similar(similar)], clock: clock)

        clock.advance(hours: 6)
        vm.refreshAllowance()
        vm.decideIndividually(["X1": .delete], cardID: "X")

        #expect(pendingIDs(vm) == ["X1"])
        #expect(vm.decisions["X2"] == .later)
        #expect(vm.decisions["S2"] == nil && vm.decisions["S3"] == nil, "Never the card that moved on top")
    }

    @Test func aDecisionForACardNotOnTopDoesNothing() async throws {
        let clock = TestClock()
        let store = InMemoryProgressStore()
        let vm = await started([.photo(photoA), .photo(photoB), .similar(similar)], clock: clock, store: store)
        let swipesBefore = vm.swipesLeft

        #expect(!vm.canDecide(.left, cardID: "S"))
        vm.decide(.left, cardID: "S")
        vm.decideIndividually(["S2": .delete], cardID: "S")

        #expect(vm.swipesLeft == swipesBefore, "No swipe spent")
        #expect(vm.index == 0)
        #expect(vm.decisions.isEmpty)
        #expect(store.decisions(for: ["A", "B", "S1", "S2", "S3"]).isEmpty, "Nothing written")
        #expect(!vm.canUndo)
    }

    @Test func undoAfterAFrontLoadBringsBackTheSwipedCard() async throws {
        let clock = TestClock()
        let vm = await started([.photo(photoA), .photo(photoB), .similar(similar)], clock: clock)

        clock.advance(hours: 6)
        vm.decide(.left, cardID: FeedCard.photo(photoA).id)
        vm.undo()

        #expect(vm.currentCard?.id == FeedCard.photo(photoA).id)
        #expect(vm.returningCard?.cardID == vm.currentCard?.id)
        #expect(pendingIDs(vm).isEmpty)
    }
}
