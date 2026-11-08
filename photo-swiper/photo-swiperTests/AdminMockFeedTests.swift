import Foundation
import Testing
@testable import photo_swiper

/// Admin Tools' mock cards in the live deck: on top right away, and never saved, charged or piled.
@MainActor
struct AdminMockFeedTests {
    private let store = InMemoryProgressStore()
    private let library = FakeLibrary()
    private let defaults = freshDefaults()

    /// A free user with a few swipes and a bin that holds almost nothing, so any real charge or
    /// pile entry would show.
    private func launch(swipes: Int = 3) async -> FeedViewModel {
        let vm = FeedViewModel(
            library: library, builder: MockFeedBuilder(), store: store,
            entitlements: TestEntitlements(isUnlocked: false), defaults: defaults,
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: swipes, tunables: .standard, now: .now)),
            freeTier: .fixed(FreeTierLimits(freeBinBytes: 1))
        )
        await vm.start()
        return vm
    }

    private func mock(_ kind: AdminMockKind) -> FeedCard {
        var rng = SeededGenerator(seed: 3)
        return AdminMockCards.card(kind, using: &rng)
    }

    @Test func anAddedCardGoesOnTop() async throws {
        let vm = await launch()
        vm.decide(.right)
        let next = try #require(vm.currentCard)
        let requests = vm.adminShowFeedRequest

        let card = mock(.similar)
        vm.adminInsertMockCard(card)

        #expect(vm.currentCard == card)
        #expect(vm.nextCard == next, "The card that was on top comes right after")
        #expect(vm.adminShowFeedRequest == requests + 1, "Asks for the feed tab")
    }

    @Test(arguments: AdminMockKind.allCases)
    func swipingAMockCardSavesNothing(_ kind: AdminMockKind) async throws {
        let vm = await launch(swipes: 1)
        let card = mock(kind)
        vm.adminInsertMockCard(card)
        let swipesBefore = vm.allowance.remaining

        #expect(vm.canDecide(.left), "Even past the pile limit")
        vm.decide(.left)

        #expect(vm.currentCard != card, "Moved on")
        #expect(vm.pendingItems.isEmpty, "Nothing in the pile")
        #expect(vm.allowance.remaining == swipesBefore, "No swipe spent")
        #expect(store.decisions(for: Set(card.items.map(\.id))).isEmpty, "Nothing saved")
        #expect(vm.decisions.keys.allSatisfy { !$0.hasPrefix(AdminMockCards.idPrefix) })
    }

    @Test func aMockCardSwipesEvenWithNoSwipesLeft() async throws {
        let vm = await launch(swipes: 0)
        vm.adminInsertMockCard(mock(.photo))

        vm.decide(.left)

        #expect(!vm.isWallPresented)
        #expect(vm.allowance.remaining == 0)
    }

    @Test func aOneByOneReviewOfAMockCardSavesNothing() async throws {
        let vm = await launch(swipes: 0)
        let card = mock(.screenshots)
        vm.adminInsertMockCard(card)

        let outcome = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, Decision.delete) })
        #expect(vm.canDecideIndividually(outcome))
        vm.decideIndividually(outcome)

        #expect(vm.currentCard != card)
        #expect(vm.pendingItems.isEmpty)
        #expect(store.decisions(for: Set(card.items.map(\.id))).isEmpty)
    }

    @Test func undoBringsAMockCardBack() async throws {
        let vm = await launch()
        let card = mock(.duplicates)
        vm.adminInsertMockCard(card)
        vm.decide(.left)

        vm.undo()

        #expect(vm.currentCard == card)
        #expect(vm.pendingItems.isEmpty)
    }

    @Test func removingMockCardsDropsOnlyTheOnesAhead() async throws {
        let vm = await launch()
        let swiped = mock(.photo)
        vm.adminInsertMockCard(swiped)
        vm.decide(.right)
        let real = try #require(vm.currentCard)
        vm.adminInsertMockCard(mock(.video))
        vm.adminInsertMockCard(mock(.similar))

        vm.adminRemoveMockCards()

        #expect(vm.currentCard == real)
        #expect(vm.cards.contains(swiped), "Already swiped, so it stays behind")
        #expect(vm.cards.filter(\.isAdminMock).count == 1)
    }

    @Test func aRelaunchLeavesMockCardsOut() async throws {
        let vm = await launch()
        vm.adminInsertMockCard(mock(.photo))
        vm.decide(.right)
        vm.decide(.right)
        let real = try #require(vm.currentCard)
        vm.adminInsertMockCard(mock(.similar))

        let relaunched = await launch()

        #expect(relaunched.currentCard == real, "Back on the same real card")
        #expect(relaunched.cards.allSatisfy { !$0.isAdminMock })
    }

    @Test func aMockCardLeavesCaughtUp() async throws {
        let vm = FeedViewModel(library: library, builder: EmptyBuilder(), store: store,
                               entitlements: TestEntitlements(), defaults: defaults)
        await vm.start()
        #expect(vm.phase == .caughtUp)

        let card = mock(.similar)
        vm.adminInsertMockCard(card)

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
