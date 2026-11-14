import Foundation
import Testing
@testable import photo_swiper

/// Records each copy it's asked for, and makes it unless told to fail.
final class FakeVideoEditor: VideoEditing, @unchecked Sendable {
    private let lock = NSLock()
    private var made: [(id: LibraryItem.ID, edit: PendingEdit)] = []
    private var failing: Set<LibraryItem.ID> = []
    private var inLibrary: Set<LibraryItem.ID> = []
    let copyBytes: Int64

    init(copyBytes: Int64 = 10_000_000) {
        self.copyBytes = copyBytes
    }

    /// Every `makeCopy` call, in order.
    var calls: [(id: LibraryItem.ID, edit: PendingEdit)] { lock.withLock { made } }
    func fail(_ ids: Set<LibraryItem.ID>) { lock.withLock { failing = ids } }
    /// Copies the library no longer has, e.g. deleted by the user.
    func removeCopies() { lock.withLock { inLibrary = [] } }

    func makeCopy(of item: LibraryItem, edit: PendingEdit, levels: CompressionLevels,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> EditedCopy {
        let fails = lock.withLock {
            made.append((item.id, edit))
            return failing.contains(item.id)
        }
        if fails { throw VideoEditError.exportFailed }
        progress(1)
        let copy = EditedCopy(id: "copy-\(item.id)-\(calls.count)", bytes: copyBytes)
        lock.withLock { _ = inLibrary.insert(copy.id) }
        return copy
    }

    func existingCopies(_ ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        lock.withLock { ids.intersection(inLibrary) }
    }
}

/// Clearing the bin with edits waiting (JUN-7's confirm, JUN-50's single export): each video is
/// exported once, its copy is saved and checked first, and the originals are deleted with the binned
/// photos in one system prompt. A copy that fails keeps its original.
@MainActor
struct ConfirmEditsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let quarter = PendingEdit(range: TrimRange(start: 0, end: 25), originalDuration: 100)

    private struct Setup {
        let vm: FeedViewModel
        let store: InMemoryProgressStore
        let editor: FakeVideoEditor
        let library: FakeLibrary
        let photo: LibraryItem
        let video: LibraryItem
        /// Each delete request, by ID, in order.
        let deletes: () -> [[LibraryItem.ID]]
    }

    /// A binned photo and an edited video. `edit` nil uses the first-quarter trim.
    private func setUp(edit: PendingEdit? = nil) async throws -> Setup {
        let library = FakeLibrary()
        var requests: [[LibraryItem.ID]] = []
        library.onDelete = { items in
            requests.append(items.map(\.id))
            return DeletionOutcome(deleted: items.map(\.id))
        }
        let store = InMemoryProgressStore()
        let editor = FakeVideoEditor()
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), store: store, entitlements: TestEntitlements(),
                               defaults: freshDefaults(), editor: editor, now: { [now] in now })
        await vm.start()
        let photo = try #require(vm.currentCard?.items.first)
        #expect(!photo.isVideo, "The mock deck starts on a photo")
        vm.decideCurrent(.left)
        var video: LibraryItem?
        while let card = vm.currentCard {
            if case .video(let item) = card { video = item; break }
            vm.decideCurrent(.right)
        }
        let edited = try #require(video)
        vm.decideEdit(edit ?? quarter, cardID: try #require(vm.currentCard?.id))
        #expect(vm.pendingEdits.map(\.id) == [edited.id])
        return Setup(vm: vm, store: store, editor: editor, library: library, photo: photo, video: edited, deletes: { requests })
    }

    @Test func eachEditedVideoIsExportedOnceAndDeletedWithThePhotosInOnePrompt() async throws {
        let s = try await setUp()

        let freed = await s.vm.deleteNow(s.vm.pendingItems)

        #expect(s.editor.calls.map(\.id) == [s.video.id], "One export for the one edited video")
        #expect(s.editor.calls.first?.edit == quarter)
        #expect(s.deletes().count == 1, "One system prompt")
        #expect(Set(s.deletes().first ?? []) == [s.photo.id, s.video.id])
        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.vm.pendingItems.isEmpty)
        #expect(freed == s.photo.bytes + s.video.bytes - s.editor.copyBytes, "The original frees what its copy saves")
        #expect(s.store.cleanupHistory().reduce(0) { $0 + $1.bytes } == freed)
    }

    @Test func theCopyIsKeptSoTheFeedNeverOffersIt() async throws {
        let s = try await setUp()

        await s.vm.deleteNow([])

        let copyID = try #require(s.store.decisions(for: [s.video.id])[s.video.id]?.edit?.copyID)
        let copy = try #require(s.store.decisions(for: [copyID])[copyID])
        #expect(copy.decision == .keep)
        #expect(copy.edit == nil)
        #expect(copy.item.bytes == s.editor.copyBytes)
        #expect(copy.item.duration == 25)
        #expect(copy.item.date == s.video.date)
        #expect(s.store.excludedFromNewSession(asOf: now).contains(copyID))
        #expect(s.store.decisions(for: [s.video.id])[s.video.id]?.settlement == .deleted)
    }

    @Test func editsAloneClearWithNoPhotosChosen() async throws {
        let s = try await setUp()

        await s.vm.deleteNow([])

        #expect(s.deletes() == [[s.video.id]])
        #expect(s.vm.pendingItems.map(\.id) == [s.photo.id], "The unchosen photo stays in the bin")
    }

    @Test func aCompressedEditIsExportedOnceToo() async throws {
        let both = PendingEdit(range: TrimRange(start: 10, end: 40), originalDuration: 100, compression: .balanced,
                               compressedBytes: 5_000_000)
        let s = try await setUp(edit: both)

        await s.vm.deleteNow([])

        #expect(s.editor.calls.count == 1)
        #expect(s.editor.calls.first?.edit == both)
    }

    @Test func aCopyThatFailsKeepsItsOriginalAndSaysWhich() async throws {
        let s = try await setUp()
        s.editor.fail([s.video.id])

        let freed = await s.vm.deleteNow(s.vm.pendingItems)

        #expect(s.deletes() == [[s.photo.id]], "Only the photo is deleted")
        #expect(freed == s.photo.bytes)
        #expect(s.vm.pendingEdits.map(\.id) == [s.video.id], "The edit waits in the bin")
        #expect(s.store.decisions(for: [s.video.id])[s.video.id]?.settlement == nil)
        #expect(s.vm.deleteNotice?.contains("Couldn't save the edited video from \(Format.day(s.video.date))") == true)
    }

    @Test func nothingIsDeletedWhenTheOnlyCopyFails() async throws {
        let s = try await setUp()
        s.editor.fail([s.video.id])

        let freed = await s.vm.deleteNow([])

        #expect(freed == nil)
        #expect(s.deletes().isEmpty)
        #expect(s.vm.deleteNotice != nil)
    }

    /// The copy is saved before the system prompt. If the user cancels it, the next clear uses that copy.
    @Test func aCancelledPromptKeepsTheCopyForTheNextClear() async throws {
        let s = try await setUp()
        s.library.onDelete = { _ in throw DeletionError.cancelled }

        #expect(await s.vm.deleteNow([]) == nil)
        let copyID = try #require(s.store.decisions(for: [s.video.id])[s.video.id]?.edit?.copyID)
        #expect(s.vm.pendingEdits.map(\.id) == [s.video.id])
        #expect(s.vm.deleteNotice?.contains("edited videos are saved") == true)

        var deleted: [LibraryItem.ID] = []
        s.library.onDelete = { items in
            deleted = items.map(\.id)
            return DeletionOutcome(deleted: deleted)
        }
        await s.vm.deleteNow([])

        #expect(s.editor.calls.count == 1, "Not exported again")
        #expect(deleted == [s.video.id])
        #expect(s.store.decisions(for: [copyID])[copyID]?.decision == .keep)
    }

    @Test func aSavedCopyThatIsGoneIsMadeAgain() async throws {
        let s = try await setUp()
        s.library.onDelete = { _ in throw DeletionError.cancelled }
        await s.vm.deleteNow([])
        s.editor.removeCopies()
        s.library.onDelete = { DeletionOutcome(deleted: $0.map(\.id)) }

        await s.vm.deleteNow([])

        #expect(s.editor.calls.count == 2)
        #expect(s.vm.pendingEdits.isEmpty)
    }

    @Test func anUndeletableOriginalKeepsItsCopyAndLeavesTheBin() async throws {
        let s = try await setUp()
        s.library.onDelete = { DeletionOutcome(undeletable: $0.map(\.id)) }

        #expect(await s.vm.deleteNow([]) == nil)

        #expect(s.vm.pendingEdits.isEmpty)
        #expect(s.store.decisions(for: [s.video.id])[s.video.id]?.settlement == .undeletable)
        #expect(s.vm.deleteNotice?.contains("can't be deleted") == true)
    }
}
