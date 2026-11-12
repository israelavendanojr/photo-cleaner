import Foundation
import Testing
@testable import photo_swiper

/// The mock builder, recording the focus each page was asked for. `@unchecked` is safe here: the
/// view model calls it one page at a time and the test reads it after `waitForPage()`, never concurrently.
private final class RecordingBuilder: FeedBuilding, @unchecked Sendable {
    private let base = MockFeedBuilder()
    private(set) var focuses: [CleanupCategory?] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        focuses.append(options.focus)
        return await base.makeSession(number: number, options: options)
    }
}

/// A dashboard suggestion focuses the feed on one kind of clutter. The card on top never changes, and
/// decisions still land on the card the user acted on (CLAUDE.md → Rules).
@MainActor
struct FeedFocusTests {
    private func started(_ builder: any FeedBuilding = MockFeedBuilder()) async -> FeedViewModel {
        let vm = FeedViewModel(library: FakeLibrary(), builder: builder, entitlements: TestEntitlements(), defaults: freshDefaults())
        await vm.start()
        return vm
    }

    private var upcoming: (FeedViewModel) -> ArraySlice<FeedCard> {
        { $0.cards.dropFirst($0.index + 1) }
    }

    @Test func theCardOnTopStaysAndOnlyMatchingCardsFollow() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        #expect(!top.matches(.video), "The mock deck starts on a photo")

        vm.focusFeed(on: .video)
        #expect(vm.currentCard?.id == top.id)
        #expect(vm.index == 0)
        await vm.waitForPage()

        #expect(vm.currentCard?.id == top.id, "A page landing after the focus doesn't move it either")
        #expect(!upcoming(vm).isEmpty)
        #expect(upcoming(vm).allSatisfy { $0.matches(.video) })
        #expect(vm.feedFocus == .video)
        #expect(vm.feedRequests == 1, "It asks for the Feed tab")
    }

    @Test func aDecisionAfterFocusingLandsOnTheCardActedOn() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let dropped = try #require(vm.cards.dropFirst().first { !$0.matches(.video) })

        vm.focusFeed(on: .video)
        vm.decide(.left, cardID: dropped.id)
        #expect(vm.decisions.isEmpty, "A card no longer in the deck can't be decided")

        vm.decide(.left, cardID: top.id)
        #expect(Set(vm.decisions.keys) == Set(top.items.map(\.id)))
        #expect(vm.currentCard?.matches(.video) == true)
    }

    @Test func pagesAreBuiltForTheFocusAndForEverythingOnceCleared() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder)
        #expect(builder.focuses == [nil])

        vm.focusFeed(on: .screenshot)
        await vm.waitForPage()
        #expect(builder.focuses.dropFirst().allSatisfy { $0 == .screenshot })
        #expect(builder.focuses.count > 1)

        let before = builder.focuses.count
        let top = vm.currentCard?.id
        vm.focusFeed(on: nil)
        await vm.waitForPage()
        #expect(vm.feedFocus == nil)
        #expect(vm.currentCard?.id == top)
        #expect(builder.focuses.dropFirst(before).allSatisfy { $0 == nil })
    }

    @Test func focusingTwiceOnTheSameKindChangesNothing() async throws {
        let vm = await started()
        vm.focusFeed(on: .video)
        await vm.waitForPage()
        let cards = vm.cards.map(\.id)

        vm.focusFeed(on: .video)
        #expect(vm.cards.map(\.id) == cards)
        #expect(vm.feedRequests == 2, "Still takes the user to the feed")
    }

    // MARK: Narrowing a page

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate(_ id: String, video: Bool = false, screenshot: Bool = false) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(createdAt: date, bytes: 1, isVideo: video, isScreenshot: screenshot))
    }

    private var input: FeedFocus.Input {
        FeedFocus.Input(
            candidates: [candidate("p1"), candidate("p2"), candidate("v", video: true), candidate("s", screenshot: true), candidate("d1"), candidate("d2")],
            duplicates: [PlannedGroup(ids: ["d1", "d2"], bestID: "d1", reason: "")],
            similar: [PlannedGroup(ids: ["p1", "p2"], bestID: "p1", reason: "")]
        )
    }

    @Test func noFocusChangesNothing() {
        #expect(FeedFocus.apply(input, focus: nil) == input)
    }

    @Test func aGroupFocusKeepsOnlyThoseGroupsAndTheirMembers() {
        let duplicates = FeedFocus.apply(input, focus: .duplicate)
        #expect(duplicates.candidates.map(\.id) == ["d1", "d2"])
        #expect(duplicates.duplicates == input.duplicates)
        #expect(duplicates.similar.isEmpty)

        let similar = FeedFocus.apply(input, focus: .similar)
        #expect(similar.candidates.map(\.id) == ["p1", "p2"])
        #expect(similar.duplicates.isEmpty)
    }

    @Test func aKindFocusKeepsThatKindAsSingleCards() {
        let videos = FeedFocus.apply(input, focus: .video)
        #expect(videos.candidates.map(\.id) == ["v"])
        #expect(videos.duplicates.isEmpty && videos.similar.isEmpty)
        #expect(FeedFocus.apply(input, focus: .screenshot).candidates.map(\.id) == ["s"])
    }
}
