import Foundation
import Testing
@testable import photo_swiper

/// Pending video edits: kept videos waiting in the bin to be replaced by a trimmed (JUN-7) or compressed
/// (JUN-50) copy. They're saved with the keep decision, survive a relaunch, and give way to a delete.
@MainActor
struct PendingEditTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let video = LibraryItem(id: "video-1", kind: .video(duration: 100), date: Date(timeIntervalSince1970: 1_800_000_000),
                                    location: nil, bytes: 400_000_000, image: .photoKit(localIdentifier: "video-1"))
    /// The first quarter: saves three quarters of the size.
    private let quarter = PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100)
    /// The whole video, compressed to a fifth of its size.
    private let compressed = PendingEdit(originalDuration: 100, compression: .balanced, compressedBytes: 80_000_000)

    private func record(_ decision: Decision, edit: PendingEdit? = nil) -> StoredDecision {
        StoredDecision(decision: decision, decidedAt: now, sessionNumber: 1, item: video, edit: edit)
    }

    private func makeStore(_ kind: ProgressStoreTests.Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    private func started(store: any ProgressStoring = InMemoryProgressStore()) async -> FeedViewModel {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), store: store, entitlements: TestEntitlements(),
                               defaults: freshDefaults(), now: { [now] in now })
        await vm.start()
        return vm
    }

    /// Keeps cards until a video is on top, and returns it.
    private func moveToVideo(_ vm: FeedViewModel) throws -> LibraryItem {
        while let card = vm.currentCard {
            if case .video(let item) = card { return item }
            vm.decideCurrent(.right)
        }
        throw CocoaError(.featureUnsupported)
    }

    // MARK: Estimate

    @Test func theEstimateScalesTheSizeByTheKeptFraction() {
        #expect(quarter.keptFraction == 0.25)
        #expect(quarter.estimatedBytes(from: 400_000_000) == 100_000_000)
        #expect(quarter.savedBytes(from: 400_000_000) == 300_000_000)
        #expect(EditedItem(item: video, edit: quarter).savedBytes == 300_000_000)
    }

    @Test func aCompressedEditUsesTheViewersEstimateNeverMoreThanTheTrimLeaves() {
        #expect(compressed.keptFraction == 1)
        #expect(compressed.newDuration == 100)
        #expect(compressed.estimatedBytes(from: 400_000_000) == 80_000_000)
        #expect(EditedItem(item: video, edit: compressed).savedBytes == 320_000_000)

        // An estimate above what the trim alone leaves is capped there.
        let both = PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100, compression: .light, compressedBytes: 150_000_000)
        #expect(both.newDuration == 25)
        #expect(both.estimatedBytes(from: 400_000_000) == 100_000_000)

        // A level without an estimate yet counts as the trim alone.
        #expect(PendingEdit(originalDuration: 100, compression: .max).savedBytes(from: 400_000_000) == 0)
    }

    @Test func anEditWithNeitherATrimNorALevelIsEmpty() {
        #expect(PendingEdit(originalDuration: 100).isEmpty)
        #expect(!quarter.isEmpty && quarter.isTrimmed && !quarter.isCompressed)
        #expect(!compressed.isEmpty && !compressed.isTrimmed && compressed.isCompressed)
    }

    // MARK: Trims saved before JUN-50

    /// The JSON JUN-7 builds wrote as `PendingTrim`, byte for byte, loads as a trim-only edit.
    @Test(arguments: [
        #"{"range":{"start":0,"end":25},"originalDuration":100}"#,
        #"{"originalDuration":100,"range":{"start":0,"end":25},"copyID":"copy-1"}"#,
    ])
    func aTrimSavedBeforeEditsDecodesAsATrimOnlyEdit(_ json: String) throws {
        let edit = try JSONDecoder().decode(PendingEdit.self, from: Data(json.utf8))
        #expect(edit.range == TrimRange(start: 0, end: 25))
        #expect(edit.originalDuration == 100)
        #expect(edit.compression == nil)
        #expect(edit.compressedBytes == nil)
        #expect(edit.copyID == (json.contains("copy-1") ? "copy-1" : nil))
        #expect(edit.estimatedBytes(from: 400_000_000) == 100_000_000, "The same estimate as before")
    }

    @Test func aTrimOnlyEditSavesTheSameJSONAsBefore() throws {
        let data = try JSONEncoder().encode(quarter)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["range", "originalDuration"], "No new keys, so an older build reads it too")
    }

    // MARK: Store

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aKeepWithATrimIsAPendingEdit(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, edit: quarter)])

        #expect(store.pendingEdits() == [EditedItem(item: video, edit: quarter)])
        #expect(store.decisions(for: [video.id])[video.id]?.edit == quarter)
        #expect(store.pile().isEmpty, "A trim isn't a delete")
        #expect(store.reviewedCount() == 1, "The video counts as kept")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aDeleteDropsTheTrim(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, edit: quarter)])

        // Even if a delete is handed one, only a keep carries a trim.
        store.save([video.id: record(.delete, edit: quarter)])

        #expect(store.pendingEdits().isEmpty)
        #expect(store.decisions(for: [video.id])[video.id]?.edit == nil)
        #expect(store.pile() == [video])
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func compressedEditsAreSavedLikeTrims(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let both = PendingEdit(range: TrimRange(start: 10, end: 60), originalDuration: 100, compression: .max, compressedBytes: 20_000_000)
        store.save([video.id: record(.keep, edit: compressed)])
        #expect(store.pendingEdits() == [EditedItem(item: video, edit: compressed)])

        store.save([video.id: record(.keep, edit: both)])
        #expect(store.pendingEdits() == [EditedItem(item: video, edit: both)])
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func anEmptyEditIsNeverSaved(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, edit: quarter)])

        store.save([video.id: record(.keep, edit: PendingEdit(originalDuration: 100))])

        #expect(store.pendingEdits().isEmpty)
        #expect(store.decisions(for: [video.id])[video.id]?.edit == nil)
        #expect(store.decisions(for: [video.id])[video.id]?.decision == .keep, "The video stays kept")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aSettledTrimIsNoLongerPending(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, edit: quarter)])
        store.settle([video.id], as: .gone)
        #expect(store.pendingEdits().isEmpty)
    }

    // MARK: Feed

    @Test func trimmingFromTheFeedKeepsTheVideoAndMovesOn() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        let cardID = try #require(vm.currentCard?.id)
        let index = vm.index

        vm.decideEdit(quarter, cardID: cardID)

        #expect(vm.index == index + 1)
        #expect(vm.decisions[item.id] == .keep)
        #expect(vm.pendingEdits.map(\.id) == [item.id])
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.editSavedBytes == quarter.savedBytes(from: item.bytes))
        #expect(vm.binBytes == vm.editSavedBytes)
        #expect(vm.binCount == 1)
    }

    @Test func aTrimFromTheFeedSaysWhatItSavesUntilTheNextDecisionOrUndo() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))
        #expect(vm.trimToast?.savedBytes == quarter.savedBytes(from: item.bytes))

        vm.decideCurrent(.right)
        #expect(vm.trimToast == nil, "The next swipe hides it, so its Undo can't reach past it")

        vm.undo()
        vm.undo()
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))
        vm.undo()
        #expect(vm.trimToast == nil)
        #expect(vm.pendingEdits.isEmpty)
    }

    @Test func trimmingACardThatIsNoLongerOnTopDoesNothing() async throws {
        let vm = await started()
        _ = try moveToVideo(vm)
        let cardID = try #require(vm.currentCard?.id)
        vm.decideCurrent(.right)
        let index = vm.index

        vm.decideEdit(quarter, cardID: cardID)

        #expect(vm.index == index)
        #expect(vm.pendingEdits.isEmpty)
    }

    @Test func trimmingWithNoSwipesLeftDoesNothing() async throws {
        // Find how many keeps reach the video, then start a free user with exactly that many swipes.
        let probe = await started()
        _ = try moveToVideo(probe)
        let tunables = SwipeAllowance.Tunables(cap: 1_000)
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), store: InMemoryProgressStore(),
                               entitlements: TestEntitlements(isUnlocked: false), defaults: freshDefaults(),
                               allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: probe.index, tunables: tunables, now: now)),
                               freeTier: .fixed(FreeTierLimits(allowance: tunables, freeBinBytes: 1_000_000_000)), now: { [now] in now })
        await vm.start()
        let item = try moveToVideo(vm)
        #expect(vm.swipesLeft == 0)
        let index = vm.index

        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))

        #expect(vm.index == index)
        #expect(vm.decisions[item.id] == nil)
        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.trimToast == nil)
    }

    @Test func trimmingACardThatIsntAVideoDoesNothing() async throws {
        let vm = await started()
        let card = try #require(vm.currentCard)
        if case .video = card { Issue.record("The mock deck starts on a photo"); return }

        vm.decideEdit(quarter, cardID: card.id)

        #expect(vm.index == 0)
        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.trimToast == nil)
    }

    /// Clearing the bin deletes only the deletions; a trimmed video is never handed to the library's delete.
    @Test func clearingTheBinLeavesTrimsAlone() async throws {
        let library = FakeLibrary()
        var deleted: [LibraryItem.ID] = []
        library.onDelete = { items in
            deleted = items.map(\.id)
            return DeletionOutcome(deleted: deleted)
        }
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), store: InMemoryProgressStore(),
                               entitlements: TestEntitlements(), defaults: freshDefaults(), now: { [now] in now })
        await vm.start()
        let video = try moveToVideo(vm)
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))
        vm.decideCurrent(.left)
        let binned = vm.pendingItems.map(\.id)
        #expect(binned.count == 1 && !binned.contains(video.id))

        await vm.deleteNow(vm.pendingItems)

        #expect(deleted == binned)
        #expect(vm.pendingEdits.map(\.id) == [video.id], "The trim waits for the confirm that makes its copy")
    }

    @Test func undoTakesTheTrimBack() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))

        vm.undo()

        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.decisions[item.id] == nil)
        #expect(vm.currentCard?.items.map(\.id) == [item.id])
    }

    /// The spec's "delete wins": a video trimmed, then binned, is deleted and its trim is dropped.
    @Test func aVideoBinnedAfterItWasTrimmedIsDeletedNotTrimmed() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))
        vm.undo()

        vm.decideCurrent(.left)

        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.pendingItems.map(\.id) == [item.id])
        #expect(store.pendingEdits().isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.edit == nil)
        #expect(vm.binBytes == item.bytes)
    }

    // MARK: Bin

    @Test func trimmingFromTheDeletesMovesTheVideoToTheTrims() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideCurrent(.left)
        #expect(vm.pendingItems.map(\.id) == [item.id])

        vm.setEdit(quarter, for: item)

        #expect(vm.pendingItems.isEmpty)
        #expect(vm.pendingEdits.map(\.id) == [item.id])
        #expect(vm.decisions[item.id] == .keep)
        #expect(store.decisions(for: [item.id])[item.id]?.edit == quarter)
    }

    @Test func editingATrimReplacesItAndCancellingKeepsTheVideoWhole() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideEdit(quarter, cardID: try #require(vm.currentCard?.id))
        let half = PendingEdit(range: TrimRange(start: 50, end: 100), originalDuration: 100)

        vm.setEdit(half, for: item)
        #expect(vm.pendingEdit(for: item.id) == half)

        vm.setEdit(nil, for: item)
        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.pendingItems.isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .keep)
        #expect(vm.binBytes == 0)
    }

    /// Choosing None takes the compression away and leaves the trim; with no trim either, the edit goes.
    @Test func removingTheCompressionKeepsTheTrimAndRemovingBothRemovesTheEdit() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        let both = PendingEdit(range: quarter.range, originalDuration: 100, compression: .balanced, compressedBytes: 50_000_000)
        vm.decideEdit(both, cardID: try #require(vm.currentCard?.id))

        vm.setEdit(PendingEdit(range: quarter.range, originalDuration: 100), for: item)
        #expect(vm.pendingEdit(for: item.id) == quarter)

        vm.setEdit(PendingEdit(originalDuration: 100), for: item)
        #expect(vm.pendingEdits.isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .keep)
        #expect(store.decisions(for: [item.id])[item.id]?.edit == nil)
    }

    @Test func anEmptyEditFromTheFeedDoesNothing() async throws {
        let vm = await started()
        _ = try moveToVideo(vm)
        let index = vm.index

        vm.decideEdit(PendingEdit(originalDuration: 100), cardID: try #require(vm.currentCard?.id))

        #expect(vm.index == index)
        #expect(vm.trimToast == nil)
    }

    @Test func compressingAVideoFromTheDeletesMovesItToTheEdits() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        vm.decideCurrent(.left)

        vm.setEdit(compressed, for: item)

        #expect(vm.pendingItems.isEmpty)
        #expect(vm.pendingEdit(for: item.id) == compressed)
        #expect(vm.binBytes == compressed.savedBytes(from: item.bytes))
    }

    @Test func settingATrimOnAVideoInNeitherSectionDoesNothing() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideCurrent(.right)

        vm.setEdit(quarter, for: item)

        #expect(vm.pendingEdits.isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.edit == nil)
    }

    @Test func pendingEditsSurviveARelaunch() async throws {
        let store = try SwiftDataProgressStore.inMemory()
        let first = await started(store: store)
        let item = try moveToVideo(first)
        first.decideEdit(quarter, cardID: try #require(first.currentCard?.id))

        let relaunched = await started(store: store)

        #expect(relaunched.pendingEdits == [EditedItem(item: item, edit: quarter)])
    }
}
