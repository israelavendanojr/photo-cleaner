import Foundation
import Testing
@testable import photo_swiper

/// Pending video trims (JUN-7): kept videos waiting in the bin to be replaced by a shorter copy. They're
/// saved with the keep decision, survive a relaunch, and give way to a delete.
@MainActor
struct PendingTrimTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let video = LibraryItem(id: "video-1", kind: .video(duration: 100), date: Date(timeIntervalSince1970: 1_800_000_000),
                                    location: nil, bytes: 400_000_000, image: .photoKit(localIdentifier: "video-1"))
    /// The first quarter: saves three quarters of the size.
    private let quarter = PendingTrim(range: TrimRange(start: 0, end: 25), originalDuration: 100)

    private func record(_ decision: Decision, trim: PendingTrim? = nil) -> StoredDecision {
        StoredDecision(decision: decision, decidedAt: now, sessionNumber: 1, item: video, trim: trim)
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
        #expect(TrimmedItem(item: video, trim: quarter).savedBytes == 300_000_000)
    }

    // MARK: Store

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aKeepWithATrimIsAPendingTrim(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, trim: quarter)])

        #expect(store.pendingTrims() == [TrimmedItem(item: video, trim: quarter)])
        #expect(store.decisions(for: [video.id])[video.id]?.trim == quarter)
        #expect(store.pile().isEmpty, "A trim isn't a delete")
        #expect(store.reviewedCount() == 1, "The video counts as kept")
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aDeleteDropsTheTrim(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, trim: quarter)])

        // Even if a delete is handed one, only a keep carries a trim.
        store.save([video.id: record(.delete, trim: quarter)])

        #expect(store.pendingTrims().isEmpty)
        #expect(store.decisions(for: [video.id])[video.id]?.trim == nil)
        #expect(store.pile() == [video])
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aSettledTrimIsNoLongerPending(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        store.save([video.id: record(.keep, trim: quarter)])
        store.settle([video.id], as: .gone)
        #expect(store.pendingTrims().isEmpty)
    }

    // MARK: Feed

    @Test func trimmingFromTheFeedKeepsTheVideoAndMovesOn() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        let cardID = try #require(vm.currentCard?.id)
        let index = vm.index

        vm.decideTrim(quarter, cardID: cardID)

        #expect(vm.index == index + 1)
        #expect(vm.decisions[item.id] == .keep)
        #expect(vm.pendingTrims.map(\.id) == [item.id])
        #expect(vm.pendingItems.isEmpty)
        #expect(vm.trimSavedBytes == quarter.savedBytes(from: item.bytes))
        #expect(vm.binBytes == vm.trimSavedBytes)
        #expect(vm.binCount == 1)
    }

    @Test func trimmingACardThatIsNoLongerOnTopDoesNothing() async throws {
        let vm = await started()
        _ = try moveToVideo(vm)
        let cardID = try #require(vm.currentCard?.id)
        vm.decideCurrent(.right)
        let index = vm.index

        vm.decideTrim(quarter, cardID: cardID)

        #expect(vm.index == index)
        #expect(vm.pendingTrims.isEmpty)
    }

    @Test func undoTakesTheTrimBack() async throws {
        let vm = await started()
        let item = try moveToVideo(vm)
        vm.decideTrim(quarter, cardID: try #require(vm.currentCard?.id))

        vm.undo()

        #expect(vm.pendingTrims.isEmpty)
        #expect(vm.decisions[item.id] == nil)
        #expect(vm.currentCard?.items.map(\.id) == [item.id])
    }

    /// The spec's "delete wins": a video trimmed, then binned, is deleted and its trim is dropped.
    @Test func aVideoBinnedAfterItWasTrimmedIsDeletedNotTrimmed() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideTrim(quarter, cardID: try #require(vm.currentCard?.id))
        vm.undo()

        vm.decideCurrent(.left)

        #expect(vm.pendingTrims.isEmpty)
        #expect(vm.pendingItems.map(\.id) == [item.id])
        #expect(store.pendingTrims().isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.trim == nil)
        #expect(vm.binBytes == item.bytes)
    }

    // MARK: Bin

    @Test func trimmingFromTheDeletesMovesTheVideoToTheTrims() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideCurrent(.left)
        #expect(vm.pendingItems.map(\.id) == [item.id])

        vm.setTrim(quarter, for: item)

        #expect(vm.pendingItems.isEmpty)
        #expect(vm.pendingTrims.map(\.id) == [item.id])
        #expect(vm.decisions[item.id] == .keep)
        #expect(store.decisions(for: [item.id])[item.id]?.trim == quarter)
    }

    @Test func editingATrimReplacesItAndCancellingKeepsTheVideoWhole() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideTrim(quarter, cardID: try #require(vm.currentCard?.id))
        let half = PendingTrim(range: TrimRange(start: 50, end: 100), originalDuration: 100)

        vm.setTrim(half, for: item)
        #expect(vm.pendingTrim(for: item.id) == half)

        vm.setTrim(nil, for: item)
        #expect(vm.pendingTrims.isEmpty)
        #expect(vm.pendingItems.isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .keep)
        #expect(vm.binBytes == 0)
    }

    @Test func settingATrimOnAVideoInNeitherSectionDoesNothing() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)
        let item = try moveToVideo(vm)
        vm.decideCurrent(.right)

        vm.setTrim(quarter, for: item)

        #expect(vm.pendingTrims.isEmpty)
        #expect(store.decisions(for: [item.id])[item.id]?.trim == nil)
    }

    @Test func pendingTrimsSurviveARelaunch() async throws {
        let store = try SwiftDataProgressStore.inMemory()
        let first = await started(store: store)
        let item = try moveToVideo(first)
        first.decideTrim(quarter, cardID: try #require(first.currentCard?.id))

        let relaunched = await started(store: store)

        #expect(relaunched.pendingTrims == [TrimmedItem(item: item, trim: quarter)])
    }
}
