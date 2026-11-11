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
    func swipingAMockCardSavesNothing(_ kind: AdminMockKind) async throws {
        let vm = await launch(swipes: 1)
        let card = mock(kind)
        vm.admin.adminInsertMockCard(card)
        let swipesBefore = vm.allowance.remaining

        #expect(vm.canDecideCurrent(.left), "Even past the pile limit")
        vm.decideCurrent(.left)

        #expect(vm.currentCard != card, "Moved on")
        #expect(vm.pendingItems.isEmpty, "Nothing in the pile")
        #expect(vm.allowance.remaining == swipesBefore, "No swipe spent")
        #expect(store.decisions(for: Set(card.items.map(\.id))).isEmpty, "Nothing saved")
        #expect(vm.decisions.keys.allSatisfy { !$0.hasPrefix(AdminMockCards.idPrefix) })
    }

    @Test func aMockCardSwipesEvenWithNoSwipesLeft() async throws {
        let vm = await launch(swipes: 0)
        vm.admin.adminInsertMockCard(mock(.photo))

        vm.decideCurrent(.left)

        #expect(!vm.isWallPresented)
        #expect(vm.allowance.remaining == 0)
    }

    @Test func aOneByOneReviewOfAMockCardSavesNothing() async throws {
        let vm = await launch(swipes: 0)
        let card = mock(.screenshots)
        vm.admin.adminInsertMockCard(card)

        let outcome = Dictionary(uniqueKeysWithValues: card.items.map { ($0.id, Decision.delete) })
        #expect(vm.canDecideCurrentIndividually(outcome))
        vm.decideCurrentIndividually(outcome)

        #expect(vm.currentCard != card)
        #expect(vm.pendingItems.isEmpty)
        #expect(store.decisions(for: Set(card.items.map(\.id))).isEmpty)
    }

    @Test func undoBringsAMockCardBack() async throws {
        let vm = await launch()
        let card = mock(.duplicates)
        vm.admin.adminInsertMockCard(card)
        vm.decideCurrent(.left)

        vm.undo()

        #expect(vm.currentCard == card)
        #expect(vm.pendingItems.isEmpty)
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
