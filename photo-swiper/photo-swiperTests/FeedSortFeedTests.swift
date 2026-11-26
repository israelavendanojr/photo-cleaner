import Foundation
import Testing
@testable import photo_swiper

/// The mock builder, recording each page's options and what it dealt. Its three pages come round again, so
/// it never runs out; cards still in the deck are left out of a page as usual. `@unchecked` is safe here: the
/// view model calls it one page at a time and the test reads it after `waitForPage()`, never concurrently.
private final class RecordingBuilder: FeedBuilding, @unchecked Sendable {
    private let base = MockFeedBuilder()
    private(set) var options: [FeedOptions] = []
    private(set) var pages: [Session] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        self.options.append(options)
        var page = await base.makeSession(number: (number - 1) % MockFeedBuilder.pageCount + 1, options: options)
        page.number = number
        pages.append(page)
        return page
    }
}

/// Deals every card it holds that isn't excluded, in the page's sort, every time. `@unchecked` is safe: one
/// page at a time.
private final class SortingDeckBuilder: FeedBuilding, @unchecked Sendable {
    private let cards: [FeedCard]

    init(_ cards: [FeedCard]) {
        self.cards = cards
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        Session(number: number, cards: options.sort.ordered(cards.filter { card in !card.items.contains { options.excluding.contains($0.id) } }))
    }
}

/// One photo, then nothing, until `gated` is set: then each page waits for `release()`, and its card says
/// which build and sort it came from. `@unchecked` is safe: every access holds `lock`.
private final class GatedBuilder: FeedBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var gated = false

    var waitingCount: Int { lock.withLock { waiting.count } }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let (call, gate) = lock.withLock { calls += 1; return (calls, gated) }
        if call == 1 { return Session(number: number, cards: [.photo(photo("first"))]) }
        guard gate else { return Session(number: number, cards: []) }
        await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
        return Session(number: number, cards: [.photo(photo("\(options.sort.rawValue)-\(call)"))])
    }

    func releaseOldest() {
        let next = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?.resume()
    }
}

private func photo(_ id: String, daysOld: Double = 0, mb: Int64 = 1) -> LibraryItem {
    LibraryItem(id: id, kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000 - daysOld * 86_400), location: nil,
                bytes: mb * 1_000_000, image: .bundled("photo-sunset"))
}

/// The sort pill (JUN-125): changing the sort drops the current card and every card after it, so the first
/// card in the new order is on top. Nothing is decided, undo's cards stay, and decisions still land on the
/// card the user acted on (CLAUDE.md → Rules).
@MainActor
struct FeedSortFeedTests {
    private func started(_ builder: any FeedBuilding = RecordingBuilder(),
                         entitlements: TestEntitlements = TestEntitlements()) async -> FeedViewModel {
        let vm = FeedViewModel(library: FakeLibrary(), builder: builder, entitlements: entitlements, defaults: freshDefaults(),
                               features: .fixed())
        await vm.start()
        await vm.waitForPage()
        return vm
    }

    private func upcoming(_ vm: FeedViewModel) -> ArraySlice<FeedCard> {
        vm.cards.dropFirst(vm.index)
    }

    private func bytes(_ card: FeedCard) -> Int64 {
        card.items.reduce(0) { $0 + $1.bytes }
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func sortingPutsTheFirstCardInTheNewOrderOnTop() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder)
        let top = try #require(vm.currentCard)

        vm.sortFeed(by: .largest)
        #expect(vm.feedSort == .largest)
        #expect(vm.currentCard == nil, "Every upcoming card goes")
        await vm.waitForPage()

        let page = try #require(builder.pages.last)
        #expect(builder.options.last?.sort == .largest)
        #expect(vm.currentCard?.id == page.cards.first?.id)
        #expect(!vm.cards.contains { $0.id == top.id })
        let sizes = upcoming(vm).prefix(page.cards.count).map(bytes)
        #expect(sizes == sizes.sorted(by: >), "Biggest first")
        #expect(vm.decisions.isEmpty, "Dropping decides nothing")
    }

    @Test func aSortKeepsTheFocusAndAFocusKeepsTheSort() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder)
        vm.focusFeed(on: .allVideos)
        await vm.waitForPage()

        let pagesBefore = builder.pages.count
        vm.sortFeed(by: .oldest)
        await vm.waitForPage()
        #expect(vm.feedFocus == .allVideos)
        #expect(upcoming(vm).allSatisfy { $0.matches(.allVideos, only: nil) })
        // Each page is in order; the first one after the sort is on top.
        let page = try #require(builder.pages.dropFirst(pagesBefore).first)
        #expect(page.cards.count >= 2)
        #expect(vm.currentCard?.id == page.cards.first?.id)
        let dates = page.cards.compactMap { $0.items.first?.date }
        #expect(dates == dates.sorted(), "Oldest first")

        vm.focusFeed(on: nil)
        await vm.waitForPage()
        #expect(vm.feedSort == .oldest)
        #expect(builder.options.last?.sort == .oldest)
    }

    @Test func cardsBeforeTheCurrentOneAreUntouched() async throws {
        let vm = await started()
        vm.decideCurrent(.right)
        vm.decideCurrent(.left)
        let behind = Array(vm.cards.prefix(vm.index))
        let decisions = vm.decisions

        vm.sortFeed(by: .newest)
        await vm.waitForPage()
        #expect(Array(vm.cards.prefix(behind.count)) == behind)
        #expect(vm.index == behind.count)
        #expect(vm.decisions == decisions)
        #expect(vm.canUndo)
        vm.undo()
        #expect(vm.currentCard?.id == behind.last?.id)
    }

    @Test func aDecisionForADroppedCardIsRefused() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let swipesBefore = vm.swipesLeft

        vm.sortFeed(by: .largest)
        await vm.waitForPage()
        #expect(!vm.canDecide(.left, cardID: top.id))
        vm.decide(.left, cardID: top.id)
        vm.decideIndividually(Dictionary(uniqueKeysWithValues: top.items.map { ($0.id, .delete) }), cardID: top.id)

        #expect(vm.decisions.isEmpty, "Never applied to the new top card")
        #expect(vm.swipesLeft == swipesBefore)
        #expect(!vm.canUndo)
    }

    @Test func aPageBuiltInTheOldOrderIsThrownAway() async throws {
        let builder = GatedBuilder()
        let vm = await started(builder)
        builder.gated = true
        vm.decideCurrent(.right)
        await until { builder.waitingCount == 1 }

        vm.sortFeed(by: .newest)
        await until { builder.waitingCount == 2 }
        // The page after the dealt one mustn't wait forever.
        builder.gated = false
        builder.releaseOldest()
        builder.releaseOldest()
        await until { vm.currentCard != nil }
        await vm.waitForPage()

        #expect(vm.currentCard?.items.first?.id.hasPrefix("newest-") == true, "Only the page in the new order is dealt")
        #expect(!vm.cards.contains { $0.items.first?.id.hasPrefix("recommended-") == true })
    }

    @Test func choosingTheSortAlreadyOnChangesNothing() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder)
        let cards = vm.cards
        let pages = builder.options.count

        vm.sortFeed(by: .recommended)
        await vm.waitForPage()
        #expect(vm.cards == cards)
        #expect(builder.options.count == pages)
    }

    /// A refill would move the similar set right behind the current card under Recommended; under a sort
    /// the order the user picked stays.
    @Test func frontLoadDoesNotReorderUnderASort() async throws {
        let similar = SimilarGroup(id: "S", items: [photo("S1", daysOld: 30), photo("S2", daysOld: 30)], bestID: "S1", reason: "")
        let cards: [FeedCard] = [.photo(photo("A")), .photo(photo("B", daysOld: 1)), .similar(similar)]
        let tunables = SwipeAllowance.Tunables(cap: 20, refillAmount: 10, refillInterval: 6 * 3600)

        func started(sort: FeedSort?) async -> (FeedViewModel, TestClock) {
            let clock = TestClock()
            let vm = FeedViewModel(
                library: FakeLibrary(), builder: SortingDeckBuilder(cards), entitlements: TestEntitlements(isUnlocked: false),
                defaults: freshDefaults(),
                allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: 5, tunables: tunables, now: clock.now)),
                freeTier: .fixed(FreeTierLimits(allowance: tunables)),
                features: .fixed([.feedSort: .everyone]),
                now: { clock.now }
            )
            await vm.start()
            await vm.waitForPage()
            if let sort {
                vm.sortFeed(by: sort)
                await vm.waitForPage()
            }
            return (vm, clock)
        }

        let (recommended, recommendedClock) = await started(sort: nil)
        recommendedClock.advance(hours: 6)
        recommended.refreshAllowance()
        #expect(recommended.cards.map(\.id) == ["item-A", "S", "item-B"], "The control: Recommended front-loads")

        let (sorted, sortedClock) = await started(sort: .newest)
        #expect(sorted.cards.map(\.id) == ["item-A", "item-B", "S"])
        sortedClock.advance(hours: 6)
        sorted.refreshAllowance()
        #expect(sorted.cards.map(\.id) == ["item-A", "item-B", "S"])
    }

    @Test func whileLockedASortAsksToUnlockAndPagesStayRecommended() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder, entitlements: TestEntitlements(isUnlocked: false))
        let cards = vm.cards

        vm.sortFeed(by: .largest)
        #expect(vm.lockedPrompt == LockedPrompt(feature: .feedSort, cardID: nil))
        #expect(vm.feedSort == .recommended)
        #expect(vm.cards == cards)
        await vm.waitForPage()
        #expect(builder.options.allSatisfy { $0.sort == .recommended })
    }

    @Test func aDowngradeFallsBackToRecommended() async throws {
        let builder = RecordingBuilder()
        let entitlements = TestEntitlements()
        let vm = await started(builder, entitlements: entitlements)
        vm.sortFeed(by: .largest)
        await vm.waitForPage()
        #expect(vm.feedSort == .largest)

        entitlements.isUnlocked = false
        #expect(vm.feedSort == .recommended, "The pill never shows a sort pages don't use")
        vm.focusFeed(on: .allVideos)
        await vm.waitForPage()
        #expect(builder.options.last?.sort == .recommended)
    }
}
