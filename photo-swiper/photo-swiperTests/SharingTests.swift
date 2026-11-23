import Foundation
import Synchronization
import Testing
@testable import photo_swiper

/// Deals one fixed deck, then nothing, so paging never changes what's on the table.
private final class ShareDeckBuilder: FeedBuilding, @unchecked Sendable {
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

/// Prepares nothing until the test says how it ends, so a share can be caught mid-download.
private final class FakeSharer: MediaSharing {
    private struct State {
        var prepared: [LibraryItem.ID] = []
        var cancellations = 0
        var waiting: CheckedContinuation<URL, Error>?
        var cancelled = false
    }

    private let state = Mutex(State())

    var prepared: [LibraryItem.ID] { state.withLock { $0.prepared } }
    var cancellations: Int { state.withLock { $0.cancellations } }

    func prepare(_ item: LibraryItem) async throws -> URL {
        state.withLock { $0.prepared.append(item.id); $0.cancelled = false }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = state.withLock { state in
                    if state.cancelled { return true }
                    state.waiting = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiting = state.withLock { state in
                state.cancellations += 1
                state.cancelled = true
                defer { state.waiting = nil }
                return state.waiting
            }
            waiting?.resume(throwing: CancellationError())
        }
    }

    /// Ends the prepare that's waiting.
    func finish(_ result: Result<URL, Error>) {
        let waiting = state.withLock { state in
            defer { state.waiting = nil }
            return state.waiting
        }
        waiting?.resume(with: result)
    }

    /// Waits until `count` prepares have started and the latest is waiting.
    func waitForPrepare(_ count: Int = 1) async {
        for _ in 0..<1000 {
            if state.withLock({ $0.prepared.count >= count && $0.waiting != nil }) { return }
            await Task.yield()
        }
    }
}

/// Sharing a card's photo or video (JUN-8) is gated like any `TierFeature`, prepares the file before the
/// share sheet, and never decides, charges, adds an undo step, writes or moves the deck.
@MainActor
struct SharingTests {
    private let tunables = SwipeAllowance.Tunables(cap: 20, refillAmount: 10, refillInterval: 6 * 3600)
    private let clock = TestClock()

    private func item(_ id: String) -> LibraryItem {
        LibraryItem(id: id, kind: .photo, date: .now, location: nil, bytes: 1_000_000, image: .bundled("photo-sunset"))
    }

    private var photo: LibraryItem { item("A") }
    private var other: LibraryItem { item("B") }
    private var video: LibraryItem {
        LibraryItem(id: "V", kind: .video(duration: 30), date: .now, location: nil, bytes: 40_000_000, image: .bundled("photo-sunset"))
    }

    private func started(
        _ cards: [FeedCard]? = nil,
        access: PlanAccess = .everyone,
        entitlements: TestEntitlements = TestEntitlements(isUnlocked: false),
        store: InMemoryProgressStore = InMemoryProgressStore(),
        sharer: FakeSharer
    ) async -> FeedViewModel {
        let vm = FeedViewModel(
            library: FakeLibrary(),
            builder: ShareDeckBuilder(cards ?? [.photo(photo), .photo(other), .video(video)]),
            store: store,
            entitlements: entitlements,
            defaults: freshDefaults(),
            allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: 5, tunables: tunables, now: clock.now)),
            freeTier: .fixed(FreeTierLimits(allowance: tunables)),
            features: .fixed([.sharing: access]),
            sharer: sharer,
            now: { [clock] in clock.now }
        )
        await vm.start()
        await vm.waitForPage()
        return vm
    }

    /// A real share folder with a file in it, as a sharer hands back.
    private func preparedFile() throws -> URL {
        let folder = try ShareFiles.makeFolder()
        let file = folder.appending(path: "IMG_0001.JPG")
        try Data([1, 2, 3]).write(to: file)
        return file
    }

    // MARK: Gating

    static let plans: [(PlanAccess, Bool)] = [
        (PlanAccess(free: .off, paid: .unlocked), false),
        (PlanAccess(free: .unlocked, paid: .off), true),
        (PlanAccess(free: .locked, paid: .unlocked), false),
        (PlanAccess(free: .unlocked, paid: .locked), true),
        (PlanAccess(free: .unlocked, paid: .unlocked), false),
        (PlanAccess(free: .unlocked, paid: .unlocked), true),
    ]

    @Test(arguments: plans)
    func theButtonFollowsTheUsersPlan(_ access: PlanAccess, _ isUnlocked: Bool) async throws {
        let sharer = FakeSharer()
        let vm = await started(access: access, entitlements: TestEntitlements(isUnlocked: isUnlocked), sharer: sharer)
        let expected: ShareButtonState? = switch access.access(isUnlocked: isUnlocked) {
        case .off: nil
        case .locked: .locked
        case .unlocked: .ready
        }
        #expect(vm.shareButton(for: photo) == expected)
        #expect(vm.shareButton(for: video) == expected)
    }

    @Test(arguments: [false, true])
    func offDoesNothing(_ isUnlocked: Bool) async throws {
        let sharer = FakeSharer()
        let vm = await started(access: PlanAccess(free: .off, paid: .off), entitlements: TestEntitlements(isUnlocked: isUnlocked), sharer: sharer)
        vm.share(photo)
        await vm.waitForShare()
        #expect(sharer.prepared.isEmpty)
        #expect(vm.lockedPrompt == nil)
        #expect(vm.sharePreparingID == nil)
        #expect(vm.sharePayload == nil)
    }

    @Test(arguments: [false, true])
    func lockedOpensThePaywallWithNoCard(_ isUnlocked: Bool) async throws {
        let sharer = FakeSharer()
        let vm = await started(access: PlanAccess(free: .locked, paid: .locked), entitlements: TestEntitlements(isUnlocked: isUnlocked), sharer: sharer)
        vm.share(photo)
        await vm.waitForShare()
        #expect(vm.lockedPrompt == LockedPrompt(feature: .sharing, cardID: nil))
        #expect(sharer.prepared.isEmpty, "Nothing is prepared behind the paywall")
        #expect(vm.sharePayload == nil)

        vm.lockedPromptDismissed()
        #expect(vm.cards.map(\.id) == [FeedCard.photo(photo).id, FeedCard.photo(other).id, FeedCard.video(video).id])
    }

    @Test(arguments: [false, true])
    func unlockedPreparesThenPresents(_ isUnlocked: Bool) async throws {
        let sharer = FakeSharer()
        let vm = await started([.video(video), .photo(photo)], entitlements: TestEntitlements(isUnlocked: isUnlocked), sharer: sharer)
        vm.share(video)
        await sharer.waitForPrepare()
        #expect(vm.sharePreparingID == video.id)
        #expect(vm.shareButton(for: video) == .preparing)
        #expect(vm.sharePayload == nil, "No sheet before the file is ready")

        let file = try preparedFile()
        sharer.finish(.success(file))
        await vm.waitForShare()
        #expect(sharer.prepared == [video.id], "The item that was tapped")
        #expect(vm.sharePayload?.url == file)
        #expect(vm.sharePayload?.itemID == video.id)
        #expect(vm.sharePreparingID == nil)
        vm.shareFinished()
    }

    @Test func adminMockCardsGetNoButton() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        let mock = item("admin-1")
        #expect(vm.shareButton(for: mock) == nil)
        vm.share(mock)
        await vm.waitForShare()
        #expect(sharer.prepared.isEmpty)
    }

    // MARK: Nothing else changes

    @Test func sharingDecidesNothingChargesNothingAndWritesNothing() async throws {
        let sharer = FakeSharer()
        let store = InMemoryProgressStore()
        let vm = await started(store: store, sharer: sharer)
        let swipesBefore = vm.swipesLeft
        let cardsBefore = vm.cards.map(\.id)

        vm.share(photo)
        await sharer.waitForPrepare()
        sharer.finish(.success(try preparedFile()))
        await vm.waitForShare()
        vm.shareFinished()

        #expect(vm.decisions.isEmpty, "Not kept, not anything")
        #expect(vm.swipesLeft == swipesBefore, "No swipe charged")
        #expect(!vm.canUndo, "No undo step")
        #expect(vm.index == 0)
        #expect(vm.currentCard?.id == FeedCard.photo(photo).id)
        #expect(vm.cards.map(\.id) == cardsBefore)
        #expect(store.decisions(for: [photo.id, other.id, video.id]).isEmpty, "Nothing written")
    }

    // MARK: Cancelling

    @Test func aSecondTapCancels() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()

        vm.share(photo)
        await vm.waitForShare()
        #expect(sharer.cancellations == 1)
        #expect(vm.sharePreparingID == nil)
        #expect(vm.sharePayload == nil)
        #expect(vm.shareNotice == nil, "Cancelling isn't a failure")
        #expect(vm.shareButton(for: photo) == .ready)
    }

    @Test func swipingTheCardAwayCancels() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()

        vm.decideCurrent(.right)
        #expect(vm.sharePreparingID == nil)
        await vm.waitForShare()
        #expect(sharer.cancellations == 1)
        #expect(vm.sharePayload == nil)
        #expect(vm.decisions == [photo.id: .keep], "The swipe decided; sharing didn't")
    }

    @Test func aFileThatArrivesAfterTheCardLeftIsThrownAway() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        let file = try preparedFile()

        vm.cancelShare()
        sharer.finish(.success(file))
        await vm.waitForShare()
        #expect(vm.sharePayload == nil)
    }

    @Test func repeatTapsWhileTheSheetIsUpAreIgnored() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        let file = try preparedFile()
        sharer.finish(.success(file))
        await vm.waitForShare()

        vm.share(photo)
        vm.share(other)
        await vm.waitForShare()
        #expect(sharer.prepared == [photo.id])
        #expect(vm.sharePayload?.url == file)
        vm.shareFinished()
    }

    // MARK: Failures

    @Test(arguments: [ShareError.downloadFailed, .gone, .exportFailed])
    func aFailureShowsAToastAndChangesNothing(_ error: ShareError) async throws {
        let sharer = FakeSharer()
        let store = InMemoryProgressStore()
        let vm = await started(store: store, sharer: sharer)
        let swipesBefore = vm.swipesLeft
        vm.share(photo)
        await sharer.waitForPrepare()

        sharer.finish(.failure(error))
        await vm.waitForShare()
        #expect(vm.shareNotice?.text == error.message)
        #expect(vm.sharePayload == nil)
        #expect(vm.sharePreparingID == nil)
        #expect(vm.decisions.isEmpty)
        #expect(vm.swipesLeft == swipesBefore)
        #expect(!vm.canUndo)
        #expect(vm.currentCard?.id == FeedCard.photo(photo).id)
        #expect(store.decisions(for: [photo.id]).isEmpty)
        #expect(vm.shareButton(for: photo) == .ready, "It can be tried again")
    }

    // MARK: Cleanup

    @Test func finishingTheSheetDeletesTheFile() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        let file = try preparedFile()
        sharer.finish(.success(file))
        await vm.waitForShare()

        vm.shareFinished()
        #expect(vm.sharePayload == nil)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path), "Its share folder is gone")
    }
}
