import Foundation
import Testing
@testable import photo_swiper

/// Records each still it's asked for, and makes it unless told to fail.
final class FakePhotoEditor: PhotoEditing, @unchecked Sendable {
    private let lock = NSLock()
    private var made: [(id: LibraryItem.ID, edit: PendingEdit)] = []
    private var failing: Set<LibraryItem.ID> = []
    private var inLibrary: Set<LibraryItem.ID> = []
    let copyBytes: Int64

    init(copyBytes: Int64 = 1_500_000) {
        self.copyBytes = copyBytes
    }

    /// Every `makeCopy` call, in order.
    var calls: [(id: LibraryItem.ID, edit: PendingEdit)] { lock.withLock { made } }
    func fail(_ ids: Set<LibraryItem.ID>) { lock.withLock { failing = ids } }

    func makeCopy(of item: LibraryItem, edit: PendingEdit, progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        let fails = lock.withLock {
            made.append((item.id, edit))
            return failing.contains(item.id)
        }
        if fails { throw EditError.saveFailed }
        progress(1)
        let copy = EditedCopy(id: "still-\(item.id)-\(calls.count)", bytes: copyBytes)
        lock.withLock { _ = inLibrary.insert(copy.id) }
        return copy
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        lock.withLock { ids.intersection(inLibrary) }
    }
}

/// Deals one fixed deck, then nothing.
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

/// Flattening a Live Photo (JUN-79): a keep that carries a flatten, queued in the bin like a video edit.
/// Clearing the bin saves the still, checks it, and only then deletes the original, in the bin's one
/// delete request. A still that fails keeps its original.
@MainActor
struct FlattenTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let liveBytes: Int64 = 4_000_000
    private let flatten = PendingEdit(originalDuration: 0, live: LiveEdit(stillBytes: 1_500_000))

    private func photo(_ id: String, live: Bool?) -> LibraryItem {
        var item = LibraryItem(id: id, kind: .photo, date: now, location: nil, bytes: Self.liveBytes, image: .bundled("photo-dusk"))
        item.isLivePhoto = live
        return item
    }

    private var live: FeedCard { .photo(photo("L", live: true)) }
    private var plain: FeedCard { .photo(photo("P", live: false)) }
    private var video: FeedCard {
        .video(LibraryItem(id: "V", kind: .video(duration: 100), date: now, location: nil, bytes: 400_000_000, image: .bundled("video-waves")))
    }

    private var similar: FeedCard {
        .similar(SimilarGroup(id: "S", items: [photo("S1", live: true), photo("S2", live: false), photo("S3", live: false)],
                              bestID: "S1", reason: "Sharpest of the set"))
    }

    private struct Setup {
        let vm: FeedViewModel
        let store: InMemoryProgressStore
        let photos: FakePhotoEditor
        let videos: FakeVideoEditor
        /// Each delete request, by ID, in order.
        let deletes: () -> [[LibraryItem.ID]]
    }

    private func started(_ cards: [FeedCard], locked: [TierFeature] = []) async -> Setup {
        let library = FakeLibrary()
        var requests: [[LibraryItem.ID]] = []
        library.onDelete = { items in
            requests.append(items.map(\.id))
            return DeletionOutcome(deleted: items.map(\.id))
        }
        let store = InMemoryProgressStore()
        let photos = FakePhotoEditor()
        let videos = FakeVideoEditor()
        let features = FeatureAvailabilityTunables.fixed(Dictionary(uniqueKeysWithValues: locked.map {
            ($0, PlanAccess(free: .locked, paid: .unlocked))
        }))
        let vm = FeedViewModel(library: library, builder: FixedDeckBuilder(cards), store: store,
                               entitlements: TestEntitlements(isUnlocked: false), defaults: freshDefaults(), features: features,
                               editor: videos, photoEditor: photos, now: { [now] in now })
        await vm.start()
        await vm.waitForPage()
        return Setup(vm: vm, store: store, photos: photos, videos: videos, deletes: { requests })
    }

    // MARK: The saved edit

    @Test func videoEditsSavedBeforeFlattenStillDecode() throws {
        let old = #"{"range":{"start":0,"end":25},"originalDuration":100,"compression":"balanced","compressedBytes":42}"#
        let edit = try JSONDecoder().decode(PendingEdit.self, from: Data(old.utf8))
        #expect(edit.live == nil && !edit.isFlatten)
        #expect(edit.range == TrimRange(start: 0, end: 25) && edit.compression == .balanced)
    }

    @Test(arguments: [nil, 1.75] as [TimeInterval?])
    func aFlattenRoundTrips(keyFrameTime: TimeInterval?) throws {
        let edit = PendingEdit(originalDuration: 0, live: LiveEdit(keyFrameTime: keyFrameTime, stillBytes: 1_200_000))
        let decoded = try JSONDecoder().decode(PendingEdit.self, from: JSONEncoder().encode(edit))
        #expect(decoded == edit)
        #expect(decoded.isFlatten && !decoded.isEmpty)
        #expect(decoded.live?.keyFrameTime == keyFrameTime)
    }

    @Test func aFlattenSavesEverythingButTheStillAndNeverDependsOnDuration() {
        #expect(flatten.estimatedBytes(from: Self.liveBytes) == 1_500_000)
        #expect(flatten.savedBytes(from: Self.liveBytes) == 2_500_000)
        let unknown = PendingEdit(originalDuration: 0, live: LiveEdit())
        #expect(unknown.savedBytes(from: Self.liveBytes) == 0, "Without a known still, it claims no savings")
    }

    // MARK: Deciding

    @Test func flatteningALivePhotoKeepsItAndQueuesTheFlatten() async throws {
        let s = await started([live, plain])
        let swipes = s.vm.swipesLeft

        s.vm.decideEdit(flatten, cardID: live.id)

        #expect(s.vm.decisions["L"] == .keep)
        #expect(s.vm.pendingEdits.map(\.id) == ["L"])
        #expect(s.vm.pendingEdits.first?.edit.isFlatten == true)
        #expect(s.vm.currentCard?.id == plain.id)
        #expect(s.vm.swipesLeft == swipes.map { $0 - 1 }, "It costs a swipe, like a keep")
        #expect(s.vm.trimToast?.isFlatten == true)
        #expect(s.vm.binBytes == 2_500_000)
    }

    @Test func aFlattenOnAPlainPhotoOrAVideoDoesNothing() async throws {
        let s = await started([plain, video])
        s.vm.decideEdit(flatten, cardID: plain.id)
        #expect(s.vm.decisions.isEmpty)
        #expect(s.vm.currentCard?.id == plain.id)

        s.vm.decideCurrent(.right)
        s.vm.decideEdit(flatten, cardID: video.id)
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.currentCard?.id == video.id)
    }

    @Test func aFlattenForACardNoLongerOnTopDoesNothing() async throws {
        let s = await started([plain, live])
        s.vm.decideEdit(flatten, cardID: live.id)
        #expect(s.vm.decisions.isEmpty)
        #expect(s.vm.pendingEdits.isEmpty)
    }

    @Test func binningAFlattenedPhotoDropsTheFlatten() async throws {
        let s = await started([live, plain])
        s.vm.decideEdit(flatten, cardID: live.id)
        s.vm.undo()
        #expect(s.vm.pendingEdits.isEmpty, "Undo takes the flatten back")

        s.vm.decide(.left, cardID: live.id)
        #expect(s.vm.pendingItems.map(\.id) == ["L"])
        #expect(s.vm.pendingEdits.isEmpty, "Deleting wins")
        #expect(s.store.pendingEdits().isEmpty)
    }

    @Test func cancellingAFlattenFromTheBinKeepsTheLivePhoto() async throws {
        let s = await started([live, plain])
        s.vm.decideEdit(flatten, cardID: live.id)
        s.vm.setEdit(nil, for: photo("L", live: true))
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.decisions["L"] == .keep)
    }

    @Test func aLockedFlattenRecordsNothing() async throws {
        let s = await started([live, plain], locked: [.livePhotoFlatten])
        let swipes = s.vm.swipesLeft

        s.vm.decideEdit(flatten, cardID: live.id)

        #expect(s.vm.decisions.isEmpty)
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.swipesLeft == swipes)
        #expect(s.vm.currentCard?.id == live.id)
        #expect(!s.vm.canUndo)
        #expect(s.store.decisions(for: ["L"]).isEmpty)
    }

    // MARK: Inside a bundle

    @Test func aFlattenFromABundleReviewAppliesOnlyToTheItemItNames() async throws {
        let s = await started([similar, plain])

        s.vm.decideIndividually(["S1": .keep, "S2": .delete, "S3": .keep],
                                edits: ["S1": flatten, "S2": flatten, "P": flatten], cardID: similar.id)

        #expect(s.vm.pendingEdits.map(\.id) == ["S1"], "Not a deleted item, nor one outside the card")
        #expect(s.vm.pendingItems.map(\.id) == ["S2"])
        #expect(s.vm.decisions["P"] == nil)
        #expect(s.vm.currentCard?.id == plain.id)
    }

    @Test func aBundleReviewForACardNoLongerOnTopQueuesNoFlatten() async throws {
        let s = await started([plain, similar])
        s.vm.decideIndividually(["S1": .keep, "S2": .keep, "S3": .keep], edits: ["S1": flatten], cardID: similar.id)
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.decisions.isEmpty)
    }

    @Test func aLockedFlattenInABundleIsLeftOutButTheReviewStillApplies() async throws {
        let s = await started([similar, plain], locked: [.livePhotoFlatten])
        s.vm.decideIndividually(["S1": .keep, "S2": .delete, "S3": .keep], edits: ["S1": flatten], cardID: similar.id)
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.decisions["S1"] == .keep)
    }

    // MARK: Clearing the bin

    @Test func flattensAndVideoEditsAreMadeFirstThenEveryOriginalGoesInOneDelete() async throws {
        let s = await started([live, video, plain])
        s.vm.decideEdit(flatten, cardID: live.id)
        s.vm.decideEdit(PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100), cardID: video.id)
        s.vm.decide(.left, cardID: plain.id)

        let freed = await s.vm.deleteNow(s.vm.pendingItems)

        #expect(s.photos.calls.map(\.id) == ["L"])
        #expect(s.videos.calls.map(\.id) == ["V"])
        #expect(s.deletes().count == 1, "One system prompt")
        #expect(Set(s.deletes().first ?? []) == ["P", "V", "L"])
        let flattenFreed = Self.liveBytes - s.photos.copyBytes
        let videoFreed = 400_000_000 - s.videos.copyBytes
        #expect(freed == Self.liveBytes + flattenFreed + videoFreed, "The photo whole, each original less its copy")
        #expect(s.vm.pendingEdits.isEmpty)
    }

    @Test func aStillThatFailsKeepsItsOriginalInTheBin() async throws {
        let s = await started([live, plain])
        s.vm.decideEdit(flatten, cardID: live.id)
        s.vm.decide(.left, cardID: plain.id)
        s.photos.fail(["L"])

        _ = await s.vm.deleteNow(s.vm.pendingItems)

        #expect(s.deletes() == [["P"]], "Never the original whose still failed")
        #expect(s.vm.pendingEdits.map(\.id) == ["L"], "It waits in the bin")
        #expect(s.vm.deleteNotice?.contains("flattened photo") == true)
    }

    @Test func aSavedStillIsNeverMadeAgainAndIsKeptAsAPlainPhoto() async throws {
        let library = FakeLibrary()
        var prompts = 0
        library.onDelete = { items in
            prompts += 1
            // The first system prompt is cancelled; the second goes through.
            if prompts == 1 { throw DeletionError.cancelled }
            return DeletionOutcome(deleted: items.map(\.id))
        }
        let store = InMemoryProgressStore()
        let photos = FakePhotoEditor()
        let vm = FeedViewModel(library: library, builder: FixedDeckBuilder([live, plain]), store: store,
                               entitlements: TestEntitlements(isUnlocked: false), defaults: freshDefaults(),
                               photoEditor: photos, now: { [now] in now })
        await vm.start()
        await vm.waitForPage()
        vm.decideEdit(flatten, cardID: live.id)

        _ = await vm.deleteNow([])
        let copyID = try #require(vm.pendingEdits.first?.edit.copyID, "The still is remembered with its flatten")
        _ = await vm.deleteNow([])

        #expect(photos.calls.count == 1, "Made once")
        #expect(vm.pendingEdits.isEmpty)
        let kept = try #require(store.decisions(for: [copyID])[copyID])
        #expect(kept.decision == .keep)
        #expect(kept.item.kind == .photo)
        #expect(kept.item.isLivePhoto == false, "The copy is a still")
    }
}
