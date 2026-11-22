import Foundation
import Testing
@testable import photo_swiper

/// Deals one fixed deck, then nothing.
private final class DraftDeckBuilder: FeedBuilding, @unchecked Sendable {
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

/// Flattens made in a bundle's one-by-one review (JUN-79): they wait with the review's draft in memory only,
/// so after a relaunch a flattened photo comes back undecided, never as a plain keep. And what the viewer
/// and the bin get to show them.
@MainActor
struct FlattenDraftTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let flatten = PendingEdit(originalDuration: 0, live: LiveEdit(stillBytes: 1_000_000))

    private func photo(_ id: String, live: Bool) -> LibraryItem {
        var item = LibraryItem(id: id, kind: .photo, date: now, location: nil, bytes: 3_000_000, image: .bundled("photo-dusk"))
        item.isLivePhoto = live
        return item
    }

    private var similar: FeedCard {
        .similar(SimilarGroup(id: "S", items: [photo("S1", live: true), photo("S2", live: false), photo("S3", live: false)],
                              bestID: "S1", reason: "Sharpest of the set"))
    }

    private let tunables = SwipeAllowance.Tunables(cap: 20, refillAmount: 10, refillInterval: 6 * 3600)

    private func started(store: InMemoryProgressStore = InMemoryProgressStore(), locked: [TierFeature] = [],
                         balance: Int = 5) async -> FeedViewModel {
        let features = FeatureAvailabilityTunables.fixed(Dictionary(uniqueKeysWithValues: locked.map {
            ($0, PlanAccess(free: .locked, paid: .unlocked))
        }))
        let vm = FeedViewModel(library: FakeLibrary(), builder: DraftDeckBuilder([similar, .photo(photo("P", live: false))]), store: store,
                               entitlements: TestEntitlements(isUnlocked: false), defaults: freshDefaults(),
                               allowanceStore: SwipeAllowanceStore(initial: SwipeAllowance(balance: balance, tunables: tunables, now: now)),
                               freeTier: .fixed(FreeTierLimits(allowance: tunables)), features: features,
                               photoEditor: FakePhotoEditor(), now: { [now] in now })
        await vm.start()
        await vm.waitForPage()
        return vm
    }

    @Test func aFlattenedPhotoWaitsWithTheDraftButIsNeverSavedAsAPlainKeep() async throws {
        let store = InMemoryProgressStore()
        let vm = await started(store: store)

        vm.saveDraft(["S1": .keep, "S2": .delete], edits: ["S1": flatten], for: "S")

        #expect(vm.draft(for: "S") == ["S1": .keep, "S2": .delete], "Reopening the review in this launch keeps it")
        #expect(vm.draftEdits(for: "S") == ["S1": flatten])
        let saved = try #require(store.loadSession()?.drafts["S"])
        #expect(saved == ["S2": .delete], "Saved without the flattened photo, so a relaunch shows it undecided")
    }

    @Test func aDraftFlattenOnAPhotoNoLongerKeptIsDropped() async throws {
        let vm = await started()
        vm.saveDraft(["S1": .delete], edits: ["S1": flatten], for: "S")
        #expect(vm.draftEdits(for: "S").isEmpty)
        #expect(vm.draft(for: "S") == ["S1": .delete])
    }

    @Test func committingTheReviewQueuesItsFlattenAndClearsTheDraft() async throws {
        let vm = await started()
        vm.saveDraft(["S1": .keep], edits: ["S1": flatten], for: "S")

        vm.decideIndividually(["S1": .keep, "S2": .keep, "S3": .delete], edits: vm.draftEdits(for: "S"), cardID: "S")

        #expect(vm.pendingEdits.map(\.id) == ["S1"])
        #expect(vm.draftEdits(for: "S").isEmpty)
        #expect(vm.draft(for: "S").isEmpty)
    }

    @Test func aReviewHeldBackAsADraftKeepsItsFlatten() async throws {
        // Out of swipes: the finished review becomes a draft, flatten and all.
        let vm = await started(balance: 0)

        vm.decideIndividually(["S1": .keep, "S2": .keep, "S3": .keep], edits: ["S1": flatten], cardID: "S")

        #expect(vm.pendingEdits.isEmpty)
        #expect(vm.draftEdits(for: "S") == ["S1": flatten])
    }

    @Test func theViewerOffersFlattenUnlessItsOffAndAsksToUnlockWhenLocked() async throws {
        let open = await started()
        #expect(open.photoEditOptions == PhotoEditOptions(canFlatten: true, flattenLocked: false))

        let locked = await started(locked: [.livePhotoFlatten])
        #expect(locked.photoEditOptions == PhotoEditOptions(canFlatten: true, flattenLocked: true))
    }

    @Test func theBinListsFlattensApartFromVideoEdits() async throws {
        let vm = await started()
        vm.decideIndividually(["S1": .keep, "S2": .keep, "S3": .keep], edits: ["S1": flatten], cardID: "S")
        #expect(vm.pendingFlattens.map(\.id) == ["S1"])
        #expect(vm.pendingVideoEdits.isEmpty)
        #expect(vm.binCount == 1, "The badge counts flattens")
        #expect(vm.binBytes == 2_000_000)
    }
}
