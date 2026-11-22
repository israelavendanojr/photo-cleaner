import Foundation
import Testing
@testable import photo_swiper

/// The mock builder, recording the focus each page was asked for. `@unchecked` is safe here: the
/// view model calls it one page at a time and the test reads it after `waitForPage()`, never concurrently.
private final class RecordingBuilder: FeedBuilding, @unchecked Sendable {
    private let base = MockFeedBuilder()
    private(set) var focuses: [FocusTarget?] = []
    private(set) var options: [FeedOptions] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        focuses.append(options.focus)
        self.options.append(options)
        return await base.makeSession(number: number, options: options)
    }
}

/// One photo, then nothing, until `gated` is set: then each page waits for `release()`, and its card says
/// which build and focus it came from. `@unchecked` is safe: every access holds `lock`.
private final class GatedBuilder: FeedBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var gated = false

    var waitingCount: Int { lock.withLock { waiting.count } }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let (call, gate) = lock.withLock { calls += 1; return (calls, gated) }
        if call == 1 { return Session(number: number, cards: [.photo(Self.photo("first"))]) }
        guard gate else { return Session(number: number, cards: []) }
        await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
        return Session(number: number, cards: [.photo(Self.photo("\(options.focus?.identifier ?? "all")-\(call)"))])
    }

    /// Lets the oldest waiting build finish.
    func releaseOldest() {
        let next = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?.resume()
    }

    static func photo(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: 1_000_000, image: .bundled("photo-sunset"))
    }
}

/// Two photos, then a video for a page focused on videos and nothing otherwise. `@unchecked` is safe:
/// one page at a time.
private final class NoVideosYetBuilder: FeedBuilding, @unchecked Sendable {
    private var dealt = false

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        defer { dealt = true }
        if !dealt { return Session(number: number, cards: [.photo(GatedBuilder.photo("a")), .photo(GatedBuilder.photo("b"))]) }
        guard options.focus == .allVideos else { return Session(number: number, cards: []) }
        let video = LibraryItem(id: "v", kind: .video(duration: 30), date: .now, location: nil, bytes: 1_000_000,
                                image: .bundled("photo-sunset"))
        return Session(number: number, cards: [.video(video)])
    }
}

/// Deals photo cards for whatever a focused page is limited to (`FeedOptions.only`), leaving out what's
/// excluded, as the real builder's pool does. Unfocused, nothing. `@unchecked` is safe: one page at a time.
private final class OnlyBuilder: FeedBuilding, @unchecked Sendable {
    private(set) var options: [FeedOptions] = []

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        self.options.append(options)
        let ids = (options.only ?? []).subtracting(options.excluding).sorted()
        return Session(number: number, cards: ids.map { .photo(GatedBuilder.photo($0)) })
    }
}

/// The filter focuses the feed on one kind of clutter. A card on top that doesn't fit is replaced by the
/// first one that does (JUN-78); one that fits stays, and clearing the focus never moves it. Nothing is
/// decided, and decisions still land on the card the user acted on (CLAUDE.md → Rules).
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

    @Test func aTopCardThatDoesntFitIsReplacedByTheFirstThatDoes() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        #expect(!top.matches(.video), "The mock deck starts on a photo")
        let firstVideo = try #require(vm.cards.first { $0.matches(.video) })
        let swipesBefore = vm.swipesLeft

        vm.focusFeed(on: .category(.video))
        #expect(vm.currentCard?.id == firstVideo.id)
        #expect(vm.index == 0)
        await vm.waitForPage()

        #expect(vm.currentCard?.id == firstVideo.id, "A page landing after the focus doesn't move it")
        #expect(vm.cards.dropFirst(vm.index).allSatisfy { $0.matches(.video) })
        #expect(!vm.cards.contains { $0.id == top.id })
        #expect(vm.decisions.isEmpty, "Dropping it decides nothing")
        #expect(vm.swipesLeft == swipesBefore)
        #expect(!vm.canUndo)
        #expect(vm.feedFocus == .category(.video))
        #expect(vm.feedRequests == 1, "It asks for the Feed tab")
    }

    @Test func aTopCardThatFitsStays() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let focus = try #require(FocusTarget.listOrder.first { !$0.isByID && top.matches($0, only: nil) })

        vm.focusFeed(on: focus)
        #expect(vm.currentCard?.id == top.id)
        await vm.waitForPage()
        #expect(vm.currentCard?.id == top.id)
        #expect(upcoming(vm).allSatisfy { $0.matches(focus, only: nil) })
    }

    @Test func aDecisionForTheDroppedTopCardIsRefused() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let swipesBefore = vm.swipesLeft

        vm.focusFeed(on: .category(.video))
        #expect(!vm.canDecide(.left, cardID: top.id))
        vm.decide(.left, cardID: top.id)
        vm.decideIndividually(Dictionary(uniqueKeysWithValues: top.items.map { ($0.id, .delete) }), cardID: top.id)

        #expect(vm.decisions.isEmpty, "Never applied to the new top card")
        #expect(vm.swipesLeft == swipesBefore)
        #expect(!vm.canUndo)

        let newTop = try #require(vm.currentCard)
        vm.decide(.left, cardID: newTop.id)
        #expect(Set(vm.decisions.keys) == Set(newTop.items.map(\.id)))
    }

    @Test func theShortenedDeckIsSavedSoARelaunchResumesOnTheNewTop() async throws {
        let store = InMemoryProgressStore()
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), store: store, entitlements: TestEntitlements(),
                               defaults: freshDefaults())
        await vm.start()
        let top = try #require(vm.currentCard)

        vm.focusFeed(on: .category(.video))
        let newTop = try #require(vm.currentCard)
        let saved = try #require(store.loadSession())
        #expect(saved.index == vm.index)
        #expect(!saved.session.cards.contains { $0.id == top.id }, "A relaunch doesn't bring the dropped card back")
        #expect(saved.session.cards[saved.index].id == newTop.id)
    }

    @Test func theDroppedTopCardsReviewAndEditGoWithIt() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let item = try #require(top.items.first)
        vm.saveDraft([item.id: .delete], for: top.id)

        vm.focusFeed(on: .category(.video))
        #expect(vm.draft(for: top.id).isEmpty)
        vm.decideEdit(PendingEdit(range: TrimRange(start: 0, end: 5), originalDuration: 100), cardID: top.id)
        #expect(vm.decisions.isEmpty, "An edit naming the dropped card does nothing")

        let newTop = try #require(vm.currentCard)
        vm.decide(.right, cardID: newTop.id)
        #expect(vm.decisions[item.id] == nil, "Its review never reaches the new top card")
    }

    @Test func clearingTheFocusNeverChangesTheTopCard() async throws {
        let vm = await started()
        vm.focusFeed(on: .category(.video))
        await vm.waitForPage()
        let top = try #require(vm.currentCard)

        vm.focusFeed(on: nil)
        #expect(vm.currentCard?.id == top.id)
        await vm.waitForPage()
        #expect(vm.currentCard?.id == top.id)
    }

    @Test func undoStillReachesACardDecidedBeforeTheFocus() async throws {
        let vm = await started()
        let decided = try #require(vm.currentCard)
        vm.decideCurrent(.right)

        vm.focusFeed(on: .category(.video))
        #expect(vm.canUndo)
        vm.undo()
        #expect(vm.currentCard?.id == decided.id, "Even though it doesn't fit the focus")
        #expect(vm.decisions.isEmpty)
    }

    @Test func withNothingLeftThatFitsTheNextPageLoads() async throws {
        let vm = await started(NoVideosYetBuilder())
        await vm.waitForPage()
        #expect(vm.currentCard?.items.first?.id == "a")

        vm.focusFeed(on: .allVideos)
        #expect(vm.currentCard == nil)
        #expect(vm.isFindingMore, "The deck says it's finding more, not caught up")
        await vm.waitForPage()
        #expect(vm.currentCard?.items.first?.id == "v")
        #expect(vm.decisions.isEmpty)
    }

    @Test func pagesAreBuiltForTheFocusAndForEverythingOnceCleared() async throws {
        let builder = RecordingBuilder()
        let vm = await started(builder)
        #expect(builder.focuses == [nil])

        vm.focusFeed(on: .category(.screenshot))
        await vm.waitForPage()
        #expect(builder.focuses.dropFirst().allSatisfy { $0 == .category(.screenshot) })
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
        vm.focusFeed(on: .category(.video))
        await vm.waitForPage()
        let cards = vm.cards.map(\.id)

        vm.focusFeed(on: .category(.video))
        #expect(vm.cards.map(\.id) == cards)
        #expect(vm.feedRequests == 2, "Still takes the user to the feed")
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Two checks from caught up overlap: "Check again", then a focus. The older one finishing first
    /// deals nothing; only the latest deals, so a deck the user is on is never replaced under them.
    @Test func onlyTheLatestCheckFromCaughtUpDeals() async throws {
        let builder = GatedBuilder()
        let vm = await started(builder)
        vm.decideCurrent(.right)
        await vm.waitForPage()
        try #require(vm.phase == .caughtUp)

        builder.gated = true
        let first = Task { await vm.checkAgain() }
        await until { builder.waitingCount == 1 }
        vm.focusFeed(on: .category(.video))
        await until { builder.waitingCount == 2 }

        builder.releaseOldest()
        await first.value
        #expect(vm.phase == .caughtUp, "The check from before the focus deals nothing")

        builder.releaseOldest()
        await until { vm.phase != .caughtUp }
        #expect(vm.currentCard?.items.first?.id.hasPrefix("video-") == true, "The latest, focused build is dealt")
    }

    // MARK: Narrowing a page

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate(_ id: String, bytes: Int64 = 1, video: Bool = false, screenshot: Bool = false) -> RankCandidate {
        RankCandidate(id: id, features: AssetFeatures(createdAt: date, bytes: bytes, isVideo: video, isScreenshot: screenshot))
    }

    private var input: FeedFocus.Input {
        FeedFocus.Input(
            candidates: [
                candidate("p1"), candidate("p2"), candidate("v", bytes: LibraryScan.largeVideoBytes, video: true),
                candidate("small-v", bytes: 1_000, video: true), candidate("s", screenshot: true), candidate("d1"), candidate("d2"),
            ],
            duplicates: [PlannedGroup(ids: ["d1", "d2"], bestID: "d1", reason: "")],
            similar: [PlannedGroup(ids: ["p1", "p2"], bestID: "p1", reason: "")]
        )
    }

    @Test func theFilterOffersEveryFocusWithLargeVideosAfterVideos() {
        #expect(FocusTarget.filterOrder == [
            .category(.duplicate), .category(.similar), .accidental, .blurry, .allVideos, .category(.video), .livePhotos,
            .category(.screenshot), .category(.burst), .documents, .category(.photo), .savedForLater,
        ])
    }

    @Test func noFocusChangesNothing() {
        #expect(FeedFocus.apply(input, focus: nil) == input)
    }

    @Test func aGroupFocusKeepsOnlyThoseGroupsAndTheirMembers() {
        let duplicates = FeedFocus.apply(input, focus: .category(.duplicate))
        #expect(duplicates.candidates.map(\.id) == ["d1", "d2"])
        #expect(duplicates.duplicates == input.duplicates)
        #expect(duplicates.similar.isEmpty)

        let similar = FeedFocus.apply(input, focus: .category(.similar))
        #expect(similar.candidates.map(\.id) == ["p1", "p2"])
        #expect(similar.duplicates.isEmpty)
    }

    @Test func aKindFocusKeepsThatKindAsSingleCards() {
        let videos = FeedFocus.apply(input, focus: .category(.video))
        #expect(videos.candidates.map(\.id) == ["v"], "Only large videos, as the dashboard counts them")
        #expect(videos.duplicates.isEmpty && videos.similar.isEmpty)
        #expect(FeedFocus.apply(input, focus: .category(.screenshot)).candidates.map(\.id) == ["s"])
    }

    @Test func allVideosKeepsEveryVideoAndLivePhotosKeepsOnlyStillsInTheSet() {
        #expect(FeedFocus.apply(input, focus: .allVideos).candidates.map(\.id) == ["v", "small-v"])
        let live = FeedFocus.apply(input, focus: .livePhotos, only: ["p1", "v", "s"])
        #expect(live.candidates.map(\.id) == ["p1", "s"], "A video is never a Live Photo")
        #expect(live.duplicates.isEmpty && live.similar.isEmpty, "Single cards, not groups")
        #expect(FeedFocus.apply(input, focus: .livePhotos).candidates.isEmpty, "No set, nothing to show")
    }

    @Test func savedForLaterKeepsTheSetAsSingleCards() {
        let later = FeedFocus.apply(input, focus: .savedForLater, only: ["d2", "small-v"])
        #expect(later.candidates.map(\.id) == ["small-v", "d2"])
        #expect(later.duplicates.isEmpty && later.similar.isEmpty)
    }

    @Test func cardsMatchAFocusByIDOnlyWhenTheirItemIsInTheSet() {
        let photo = FeedCard.photo(GatedBuilder.photo("a"))
        #expect(photo.matches(.savedForLater, only: ["a"]))
        #expect(!photo.matches(.savedForLater, only: ["b"]))
        #expect(!photo.matches(.livePhotos, only: nil), "The view model can't tell a Live Photo: new pages bring them")
        #expect(!photo.matches(.allVideos, only: nil))
    }

    // MARK: Live Photos and saved for later

    @Test func aLivePhotoFocusDealsOnlyPhotos() async throws {
        let vm = await started()
        vm.focusFeed(on: .livePhotos)
        await vm.waitForPage()
        let top = try #require(vm.currentCard)
        #expect({ if case .photo = top { true } else { false } }())
        #expect(!upcoming(vm).isEmpty)
        #expect(upcoming(vm).allSatisfy { if case .photo = $0 { true } else { false } })
    }

    /// What was saved for later sits out a day before an ordinary page offers it again. Focused on it, it's
    /// offered now, and the cooldown is back as soon as the focus is cleared.
    @Test func savedForLaterIsOfferedDuringItsCooldownOnlyWhileFocused() async throws {
        let store = InMemoryProgressStore()
        let saved = GatedBuilder.photo("saved")
        store.save([saved.id: StoredDecision(decision: .later, decidedAt: .now, sessionNumber: 0, item: saved)])
        let builder = RecordingBuilder()
        let vm = FeedViewModel(library: FakeLibrary(), builder: builder, store: store, entitlements: TestEntitlements(),
                               defaults: freshDefaults())
        await vm.start()
        #expect(builder.options.last?.excluding.contains(saved.id) == true, "Sitting out its cooldown")

        vm.focusFeed(on: .savedForLater)
        await vm.waitForPage()
        let focused = try #require(builder.options.last)
        #expect(focused.focus == .savedForLater)
        #expect(focused.only == [saved.id])
        #expect(!focused.excluding.contains(saved.id))

        // The focus dropped the photo on top and found nothing to deal, so the feed is caught up, and
        // clearing it checks again in its own task.
        let pagesBefore = builder.options.count
        vm.focusFeed(on: nil)
        await until { builder.options.count > pagesBefore }
        let unfocused = try #require(builder.options.last)
        #expect(unfocused.only == nil)
        #expect(unfocused.excluding.contains(saved.id), "The cooldown applies again")
    }

    /// Saved for later again while focused on it, an item doesn't come straight back: each comes up once per focus.
    @Test func savedForLaterShowsEachItemOncePerFocus() async throws {
        let store = InMemoryProgressStore()
        let items = ["a", "b"].map(GatedBuilder.photo)
        store.save(Dictionary(uniqueKeysWithValues: items.map { ($0.id, StoredDecision(decision: .later, decidedAt: .now, sessionNumber: 0, item: $0)) }))
        let builder = OnlyBuilder()
        let vm = FeedViewModel(library: FakeLibrary(), builder: builder, store: store, entitlements: TestEntitlements(),
                               defaults: freshDefaults())
        await vm.start()
        #expect(vm.phase == .caughtUp, "Unfocused, the builder has nothing")

        vm.focusFeed(on: .savedForLater)
        await until { vm.phase == .feed }
        #expect(vm.cards.flatMap(\.items).map(\.id) == ["a", "b"])

        vm.decideCurrent(.up)
        vm.decideCurrent(.up)
        await vm.waitForPage()
        #expect(store.laterIDs() == ["a", "b"], "Still saved for later")
        let last = try #require(builder.options.last)
        #expect(last.excluding.isSuperset(of: ["a", "b"]), "Dealt once this focus, not again")
    }
}
