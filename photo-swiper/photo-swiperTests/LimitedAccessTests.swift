import Foundation
import Testing
@testable import photo_swiper

/// Under limited access PhotoKit only sees the user's selection, so "not found" doesn't mean
/// "deleted". Nothing is settled as gone unless the app has full access (JUN-22, S-3).
@MainActor
struct LimitedAccessTests {
    private let library = FakeLibrary()
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)
    /// Shared across relaunches within a test, like the real app's defaults.
    private let defaults = freshDefaults()

    private func makeStore(_ kind: ProgressStoreTests.Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    private func launch(_ store: any ProgressStoring) async -> FeedViewModel {
        let vm = FeedViewModel(library: library, builder: MockFeedBuilder(), store: store, entitlements: TestEntitlements(), defaults: defaults, now: { [clock] in clock })
        await vm.start()
        return vm
    }

    /// Lets the view model's change-observing task run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func settlement(_ id: LibraryItem.ID, in store: any ProgressStoring) -> Settlement? {
        store.decisions(for: [id])[id]?.settlement
    }

    // MARK: Restore

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func pileItemsOutsideTheSelectionStayPendingAcrossARelaunch(_ kind: ProgressStoreTests.Kind) async throws {
        let store = try makeStore(kind)
        let vm = await launch(store)
        vm.decideCurrent(.left)
        vm.decideCurrent(.left)
        let pending = vm.pendingItems.map(\.id)
        try #require(pending.count == 2)
        let hidden = pending[0], visible = pending[1]

        // The user narrows the selection; iOS relaunches the app.
        library.access = .limited
        library.gone = [hidden]
        let limited = await launch(store)

        #expect(limited.pendingItems.map(\.id) == [visible], "Only what the app can see is offered for deletion")
        #expect(settlement(hidden, in: store) == nil, "Not settled as gone")
        #expect(Set(store.pile().map(\.id)) == Set(pending), "Still in the stored pile")
        #expect(store.excludedFromNewSession(asOf: clock).contains(hidden), "Still decided, so not offered again")

        // Full access again: it's back in the pile.
        library.access = .full
        library.gone = []
        let full = await launch(store)
        #expect(Set(full.pendingItems.map(\.id)) == Set(pending))
    }

    // MARK: Delete

    @Test func deletingUnderLimitedAccessLeavesUnseenItemsPending() async throws {
        let store = InMemoryProgressStore()
        let vm = await launch(store)
        vm.decideCurrent(.left)
        vm.decideCurrent(.left)
        let pending = vm.pendingItems
        try #require(pending.count == 2)
        library.access = .limited
        library.onDelete = { items in DeletionOutcome(deleted: [items[0].id], missing: [items[1].id]) }

        #expect(await vm.deleteNow(pending) == pending[0].bytes)

        #expect(settlement(pending[0].id, in: store) == .deleted)
        #expect(settlement(pending[1].id, in: store) == nil, "Not found isn't gone under limited access")
        #expect(store.pile().map(\.id) == [pending[1].id])
        #expect(vm.deleteNotice?.contains("outside the photos") == true)
    }

    @Test func deletingUnderFullAccessStillSettlesMissingItemsAsGone() async throws {
        let store = InMemoryProgressStore()
        let vm = await launch(store)
        vm.decideCurrent(.left)
        vm.decideCurrent(.left)
        let pending = vm.pendingItems
        library.onDelete = { items in DeletionOutcome(deleted: [items[0].id], missing: [items[1].id]) }

        await vm.deleteNow(pending)

        #expect(settlement(pending[1].id, in: store) == .gone)
        #expect(store.pile().isEmpty)
        #expect(vm.deleteNotice == nil)
    }

    // MARK: Changes while running

    @Test func aShrinkingSelectionSettlesNothing() async throws {
        let store = InMemoryProgressStore()
        let vm = await launch(store)
        vm.decideCurrent(.left)
        let pendingID = try #require(vm.pendingItems.first?.id)
        let upcoming = vm.cards[5]
        let countBefore = vm.cards.count
        library.access = .limited

        library.vanish([pendingID, upcoming.items[0].id])
        await settle { vm.cards.count < countBefore }

        #expect(settlement(pendingID, in: store) == nil)
        #expect(settlement(upcoming.items[0].id, in: store) == nil)
        #expect(!vm.cards.contains { $0.id == upcoming.id }, "Cards it can't show any more still leave the deck")
        #expect(vm.pendingItems.isEmpty, "Hidden from the pile while out of reach")
        #expect(store.pile().map(\.id) == [pendingID])
    }

    @Test func itemsDeletedElsewhereUnderFullAccessAreStillSettledAsGone() async throws {
        let store = InMemoryProgressStore()
        let vm = await launch(store)
        vm.decideCurrent(.left)
        let pendingID = try #require(vm.pendingItems.first?.id)

        library.vanish([pendingID])
        await settle { vm.pendingItems.isEmpty }

        #expect(settlement(pendingID, in: store) == .gone)
        #expect(store.pile().isEmpty)
    }

    // MARK: Repair

    private func storeWithWronglyGoneItem() -> (InMemoryProgressStore, LibraryItem) {
        let store = InMemoryProgressStore()
        let item = LibraryItem(id: "wrongly-gone", kind: .photo, date: clock, location: nil, bytes: 1_000, image: .bundled("photo-sunset"))
        store.save([item.id: StoredDecision(decision: .delete, decidedAt: clock, sessionNumber: 0, item: item)])
        store.settle([item.id], as: .gone)
        return (store, item)
    }

    @Test func fullAccessReopensItemsWronglySettledAsGone() async throws {
        let (store, item) = storeWithWronglyGoneItem()

        let vm = await launch(store)

        #expect(settlement(item.id, in: store) == nil)
        #expect(vm.pendingItems.contains { $0.id == item.id }, "Back in the pile, still needing confirmation")
    }

    @Test func theRepairLeavesTrulyGoneItemsAlone() async throws {
        let (store, item) = storeWithWronglyGoneItem()
        library.gone = [item.id]

        _ = await launch(store)

        #expect(settlement(item.id, in: store) == .gone)
    }

    @Test func theRepairRunsOnce() async throws {
        _ = await launch(InMemoryProgressStore())
        let (store, item) = storeWithWronglyGoneItem()

        _ = await launch(store)

        #expect(settlement(item.id, in: store) == .gone, "Later gone items are left to the normal rules")
    }

    @Test func theRepairWaitsForFullAccess() async throws {
        let (store, item) = storeWithWronglyGoneItem()
        library.access = .limited

        _ = await launch(store)

        #expect(settlement(item.id, in: store) == .gone)

        library.access = .full
        _ = await launch(store)
        #expect(settlement(item.id, in: store) == nil, "Repaired on the first launch with full access")
    }

    // MARK: Adding photos

    @Test func photosAddedToTheSelectionRejoinThePile() async throws {
        let store = InMemoryProgressStore()
        let vm = await launch(store)
        vm.decideCurrent(.left)
        let pendingID = try #require(vm.pendingItems.first?.id)
        library.access = .limited
        library.gone = [pendingID]
        let limited = await launch(store)
        #expect(limited.pendingItems.isEmpty)

        library.pickerAdds = [pendingID]
        await limited.addMorePhotos()

        #expect(limited.pendingItems.map(\.id) == [pendingID])
    }
}
