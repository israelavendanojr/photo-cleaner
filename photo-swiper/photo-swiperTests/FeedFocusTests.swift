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

/// A dashboard row focuses the feed on one kind of clutter. The card on top never changes, and
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

        vm.focusFeed(on: .category(.video))
        #expect(vm.currentCard?.id == top.id)
        #expect(vm.index == 0)
        await vm.waitForPage()

        #expect(vm.currentCard?.id == top.id, "A page landing after the focus doesn't move it either")
        #expect(!upcoming(vm).isEmpty)
        #expect(upcoming(vm).allSatisfy { $0.matches(.video) })
        #expect(vm.feedFocus == .category(.video))
        #expect(vm.feedRequests == 1, "It asks for the Feed tab")
    }

    @Test func aDecisionAfterFocusingLandsOnTheCardActedOn() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        let dropped = try #require(vm.cards.dropFirst().first { !$0.matches(.video) })

        vm.focusFeed(on: .category(.video))
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

    @Test func aLivePhotoFocusKeepsTheTopCardAndDealsOnlyPhotos() async throws {
        let vm = await started()
        let top = try #require(vm.currentCard)
        vm.focusFeed(on: .livePhotos)
        await vm.waitForPage()
        #expect(vm.currentCard?.id == top.id)
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

        vm.focusFeed(on: nil)
        await vm.waitForPage()
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
