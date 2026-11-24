import Foundation
import Synchronization
import Testing
@testable import photo_swiper

/// Deals its pages in order, then nothing, so paging never changes what's on the table unexpectedly.
/// Unchecked like `LockedFeatureTests`' builder: the view model calls it from one task at a time.
private final class ShareDeckBuilder: FeedBuilding, @unchecked Sendable {
    private var pages: [[FeedCard]]

    init(_ pages: [[FeedCard]]) {
        self.pages = pages
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        Session(number: number, cards: pages.isEmpty ? [] : pages.removeFirst())
    }
}

/// Prepares nothing until the test says how each prepare ends, so a share can be caught mid-download.
/// With `ignoresCancel`, a cancelled prepare keeps waiting, as a PhotoKit request may, so a test can
/// deliver its file late.
private final class FakeSharer: MediaSharing {
    private struct State {
        var prepared: [LibraryItem.ID] = []
        var cancellations = 0
        var ignoresCancel = false
        var waiting: [Int: CheckedContinuation<URL, Error>] = [:]
        var cancelled: Set<Int> = []
    }

    private let state = Mutex(State())

    var prepared: [LibraryItem.ID] { state.withLock { $0.prepared } }
    var cancellations: Int { state.withLock { $0.cancellations } }

    func ignoreCancel() {
        state.withLock { $0.ignoresCancel = true }
    }

    func prepare(_ item: LibraryItem) async throws -> URL {
        let number = state.withLock { state in
            state.prepared.append(item.id)
            return state.prepared.count - 1
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = state.withLock { state in
                    if state.cancelled.contains(number), !state.ignoresCancel { return true }
                    state.waiting[number] = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiting = state.withLock { state in
                state.cancellations += 1
                state.cancelled.insert(number)
                return state.ignoresCancel ? nil : state.waiting.removeValue(forKey: number)
            }
            waiting?.resume(throwing: CancellationError())
        }
    }

    /// Ends prepare number `number` (counting from 0), or the latest one waiting.
    func finish(_ result: Result<URL, Error>, prepare number: Int? = nil) {
        let waiting = state.withLock { state in
            guard let key = number ?? state.waiting.keys.max() else { return nil as CheckedContinuation<URL, Error>? }
            return state.waiting.removeValue(forKey: key)
        }
        waiting?.resume(with: result)
    }

    /// Waits until `count` prepares have started and the latest is waiting. Returning before that would
    /// let `finish` find nothing to resume and leave the prepare (and the test) suspended forever.
    func waitForPrepare(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        await poll(sourceLocation: sourceLocation) {
            self.state.withLock { $0.prepared.count >= count && $0.waiting[count - 1] != nil }
        }
    }
}

/// Polls until `condition` holds, for work the test can't await directly.
@MainActor
private func eventually(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async {
    await poll(sourceLocation: sourceLocation, condition)
}

/// Bounded by time, not by a count of yields: under load (a simulator busy with other suites) a fixed
/// number of yields can run out before the work does. A timeout fails the test rather than hanging it.
private func poll(timeout: Duration = .seconds(10), sourceLocation: SourceLocation, _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
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
        later: [[FeedCard]] = [],
        access: PlanAccess = .everyone,
        entitlements: TestEntitlements = TestEntitlements(isUnlocked: false),
        store: InMemoryProgressStore = InMemoryProgressStore(),
        sharer: FakeSharer
    ) async -> FeedViewModel {
        let vm = FeedViewModel(
            library: FakeLibrary(),
            builder: ShareDeckBuilder([cards ?? [.photo(photo), .photo(other), .video(video)]] + later),
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

    @Test func aFileThatArrivesAfterACancelIsThrownAway() async throws {
        let sharer = FakeSharer()
        sharer.ignoreCancel()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        let file = try preparedFile()

        vm.cancelShare()
        sharer.finish(.success(file))
        await vm.waitForShare()
        #expect(vm.sharePayload == nil)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path), "Its share folder is removed")
    }

    @Test func aCancelledShareThatLandsLateLeavesTheNewOneAlone() async throws {
        let sharer = FakeSharer()
        sharer.ignoreCancel()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare(1)
        vm.share(photo)
        #expect(vm.sharePreparingID == nil, "The second tap cancelled")
        vm.share(photo)
        await sharer.waitForPrepare(2)

        let late = try preparedFile()
        sharer.finish(.success(late), prepare: 0)
        await eventually { !FileManager.default.fileExists(atPath: late.deletingLastPathComponent().path) }
        #expect(!FileManager.default.fileExists(atPath: late.deletingLastPathComponent().path), "The stale file is removed")
        #expect(vm.sharePayload == nil, "The stale file never opens the sheet")
        #expect(vm.sharePreparingID == photo.id, "The newer share is still being prepared")

        let file = try preparedFile()
        sharer.finish(.success(file), prepare: 1)
        await vm.waitForShare()
        #expect(vm.sharePayload?.url == file)
        vm.shareFinished()
    }

    @Test func aFailureAfterACancelShowsNothing() async throws {
        let sharer = FakeSharer()
        sharer.ignoreCancel()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        vm.cancelShare()

        sharer.finish(.failure(ShareError.downloadFailed))
        await vm.waitForShare()
        #expect(vm.shareNotice == nil)
    }

    @Test func aPageLandingWhileSharingDoesntCancelIt() async throws {
        let sharer = FakeSharer()
        let first = (0..<40).map { FeedCard.photo(item("P\($0)")) }
        let second = (40..<50).map { FeedCard.photo(item("P\($0)")) }
        let vm = await started(first, later: [second], entitlements: TestEntitlements(isUnlocked: true), sharer: sharer)
        for _ in 0..<35 { vm.decideCurrent(.right) }
        let top = try #require(vm.currentCard?.items.first)
        #expect(top.id == "P35")

        // The last swipe started the next page; it lands while the file is prepared, and trims the
        // decided cards behind (more than `keptBehind`), which shifts the deck under the top card.
        vm.share(top)
        await sharer.waitForPrepare()
        await vm.waitForPage()
        #expect(vm.cards.count < 50, "Cards behind were trimmed")
        #expect(vm.currentCard?.items.first?.id == top.id)
        #expect(sharer.cancellations == 0)
        #expect(vm.sharePreparingID == top.id)
        vm.cancelShare()
    }

    @Test func onlyTheTopCardCanShare() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(other)
        await vm.waitForShare()
        #expect(sharer.prepared.isEmpty)
        #expect(vm.sharePreparingID == nil)
    }

    @Test func aSecondTapCancelsEvenIfThePlanLockedMeanwhile() async throws {
        let sharer = FakeSharer()
        let entitlements = TestEntitlements(isUnlocked: true)
        let vm = await started(access: PlanAccess(free: .locked, paid: .unlocked), entitlements: entitlements, sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()

        entitlements.isUnlocked = false
        vm.share(photo)
        await vm.waitForShare()
        #expect(sharer.cancellations == 1)
        #expect(vm.lockedPrompt == nil, "A cancel, not the paywall")
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

    @Test func aSheetThatCouldntOpenSaysSoAndDeletesTheFile() async throws {
        let sharer = FakeSharer()
        let vm = await started(sharer: sharer)
        vm.share(photo)
        await sharer.waitForPrepare()
        let file = try preparedFile()
        sharer.finish(.success(file))
        await vm.waitForShare()

        vm.shareCouldNotPresent()
        #expect(vm.sharePayload == nil)
        #expect(vm.shareNotice != nil)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(vm.shareButton(for: photo) == .ready, "It can be tried again")
    }

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
