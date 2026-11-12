import Foundation
import SwiftData
import Testing
@testable import photo_swiper

/// One save per swipe, and the deck's cards encoded only when they change (JUN-45, Q-2).
@MainActor
struct ProgressWritesTests {
    private let session = MockFeedBuilder().makeSessionNow(number: 3)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ item: LibraryItem, _ decision: Decision, at date: Date? = nil) -> StoredDecision {
        StoredDecision(decision: decision, decidedAt: date ?? now, sessionNumber: session.number, item: item)
    }

    private func makeStore(_ kind: ProgressStoreTests.Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "writes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "default.store")
    }

    // MARK: The store contract

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aCommitWritesDecisionsAndTheWholeDeck(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let item = session.items[0]
        let saved = SavedSession(session: session, index: 1, marks: [:], finished: false)

        #expect(store.commit([item.id: record(item, .delete)], deck: .full(saved)))

        #expect(store.decisions(for: [item.id])[item.id] == record(item, .delete))
        #expect(store.loadSession() == saved)
        #expect(store.pile() == [item])
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aPositionWriteKeepsTheCardsAndMovesWhereTheUserIs(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let first = session.items[0], second = session.items[1]
        store.commit([:], deck: .full(SavedSession(session: session, index: 0, marks: [:], finished: false)))

        let marks = ["group": Set([second.id])]
        let drafts = ["card": [first.id: Decision.keep]]
        #expect(store.commit([first.id: record(first, .keep)], deck: .position(number: session.number, index: 2, marks: marks, drafts: drafts)))

        #expect(store.loadSession() == SavedSession(session: session, index: 2, marks: marks, finished: false, drafts: drafts))
        #expect(store.decisions(for: [first.id])[first.id]?.decision == .keep)
    }

    @Test(arguments: ProgressStoreTests.Kind.allCases)
    func aPositionWriteWithoutThatDeckWritesNothing(_ kind: ProgressStoreTests.Kind) throws {
        let store = try makeStore(kind)
        let item = session.items[0]
        let position = DeckWrite.position(number: session.number, index: 1, marks: [:], drafts: [:])

        #expect(!store.commit([item.id: record(item, .delete)], deck: position))
        #expect(store.decisions(for: [item.id]).isEmpty)
        #expect(store.loadSession() == nil)

        store.commit([:], deck: .full(SavedSession(session: session, index: 0, marks: [:], finished: false)))
        #expect(!store.commit([item.id: record(item, .delete)], deck: .position(number: session.number + 1, index: 1, marks: [:], drafts: [:])))
        #expect(store.decisions(for: [item.id]).isEmpty)
        #expect(store.loadSession()?.index == 0)
    }

    /// Force-quitting right after a swipe loses nothing: a fresh container on the same file has it all.
    @Test func aCommitIsOnDiskWhenItReturns() throws {
        let url = try temporaryStoreURL()
        let item = session.items[0]
        let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)
        store.commit([:], deck: .full(SavedSession(session: session, index: 0, marks: [:], finished: false)))
        store.commit([item.id: record(item, .delete)], deck: .position(number: session.number, index: 1, marks: ["g": [item.id]], drafts: [:]))

        let reopened = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)
        #expect(reopened.decisions(for: [item.id])[item.id] == record(item, .delete))
        #expect(reopened.loadSession() == SavedSession(session: session, index: 1, marks: ["g": [item.id]], finished: false))
        #expect(reopened.reviewedCount() == 1)
    }

    // MARK: The mirror

    /// After every kind of write, the counts the mirror gives match a store that reads them fresh from disk.
    @Test(arguments: [1, 2, 3] as [UInt64])
    func theMirrorAlwaysMatchesWhatIsOnDisk(seed: UInt64) throws {
        let url = try temporaryStoreURL()
        let container = try SwiftDataProgressStore.makeContainer(url: url)
        let store = SwiftDataProgressStore(container: container, defaults: nil)
        var rng = SplitMix64(seed: seed)
        let items = (0..<40).map { n in
            LibraryItem(id: "item-\(n)", kind: .photo, date: now, location: nil, bytes: 1_000, image: .photoKit(localIdentifier: "item-\(n)"))
        }
        let decisions: [Decision] = [.keep, .delete, .later]
        let settlements: [Settlement] = [.deleted, .gone, .undeletable]

        for step in 0..<200 {
            let some = Set(items.shuffled(using: &rng).prefix(Int(rng.next() % 5) + 1))
            switch rng.next() % 9 {
            case 0...3:
                store.save(Dictionary(uniqueKeysWithValues: some.map { item in
                    let at = now.addingTimeInterval(-Double(rng.next() % 3) * StoredDecision.laterCooldown / 2)
                    return (item.id, Optional(record(item, decisions[Int(rng.next() % 3)], at: at)))
                }))
            case 4:
                store.save(Dictionary(uniqueKeysWithValues: some.map { ($0.id, StoredDecision?.none) }))
            case 5:
                store.settle(Set(some.map(\.id)), as: settlements[Int(rng.next() % 3)])
            case 6:
                store.reopen(Set(some.map(\.id)))
            case 7:
                let item = some.first!
                store.commit([item.id: record(item, decisions[Int(rng.next() % 3)])],
                             deck: .full(SavedSession(session: session, index: step % 5, marks: [:], finished: false)))
            default:
                if step % 50 == 49 { store.reset() }
            }

            let fresh = SwiftDataProgressStore(container: container, defaults: nil)
            #expect(store.reviewedCount() == fresh.reviewedCount(), "step \(step)")
            #expect(store.excludedFromNewSession(asOf: now) == fresh.excludedFromNewSession(asOf: now), "step \(step)")
            #expect(store.excludedFromNewSession(asOf: now.addingTimeInterval(StoredDecision.laterCooldown)) ==
                fresh.excludedFromNewSession(asOf: now.addingTimeInterval(StoredDecision.laterCooldown)), "step \(step)")
        }
    }

    // MARK: The view model

    /// Lets the view model's change-observing task run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func swipesWriteOnlyThePositionUntilTheCardsChange() async throws {
        let store = CountingStore()
        let builder = MockFeedBuilder()
        let library = FakeLibrary()
        let vm = FeedViewModel(library: library, builder: builder, store: store, entitlements: TestEntitlements(), now: { [now] in now })
        await vm.start()
        await vm.waitForPage()
        let afterDeal = store.fullWrites

        for _ in 0..<3 { vm.decideCurrent(.right) }
        await vm.waitForPage()
        #expect(store.fullWrites == afterDeal, "Swipes don't encode the cards again")
        #expect(store.positionWrites >= 3)
        #expect(store.decisions(for: Set(vm.cards.prefix(3).flatMap(\.items).map(\.id))).count == vm.cards.prefix(3).flatMap(\.items).count)

        vm.undo()
        #expect(store.fullWrites == afterDeal)

        // An item deleted elsewhere leaves a card ahead, which changes the cards: they're written whole.
        let ahead = try #require(vm.cards.last).items.map(\.id)
        let changes = store.fullWrites
        library.vanish(Set(ahead))
        await settle { store.fullWrites > changes }
        #expect(store.fullWrites == changes + 1)
        #expect(store.loadSession()?.session == vm.session)

        let relaunched = FeedViewModel(library: FakeLibrary(), builder: builder, store: store, entitlements: TestEntitlements(), now: { [now] in now })
        await relaunched.start()
        #expect(relaunched.cards.map(\.id) == vm.cards.map(\.id))
        #expect(relaunched.index == vm.index)
    }
}

/// An in-memory store that counts how the deck is written.
@MainActor
private final class CountingStore: ProgressStoring {
    private let base = InMemoryProgressStore()
    private(set) var fullWrites = 0
    private(set) var positionWrites = 0

    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision] { base.decisions(for: ids) }
    func save(_ changes: [LibraryItem.ID: StoredDecision?]) { base.save(changes) }
    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) { base.settle(ids, as: settlement) }
    func goneIDs() -> Set<LibraryItem.ID> { base.goneIDs() }
    func reopen(_ ids: Set<LibraryItem.ID>) { base.reopen(ids) }
    func pile() -> [LibraryItem] { base.pile() }
    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID> { base.excludedFromNewSession(asOf: now) }
    func reviewedCount() -> Int { base.reviewedCount() }
    func freedBytes() -> Int64 { base.freedBytes() }
    func lastSessionNumber() -> Int { base.lastSessionNumber() }
    func recordCleanup(_ entries: [CleanupEntry]) { base.recordCleanup(entries) }
    func cleanupHistory() -> [CleanupEntry] { base.cleanupHistory() }
    func loadSession() -> SavedSession? { base.loadSession() }

    func saveSession(_ saved: SavedSession?) {
        fullWrites += 1
        base.saveSession(saved)
    }

    func commit(_ changes: [LibraryItem.ID: StoredDecision?], deck: DeckWrite) -> Bool {
        let written = base.commit(changes, deck: deck)
        if written, case .full = deck { fullWrites += 1 }
        if written, case .position = deck { positionWrites += 1 }
        return written
    }

    var skipFavorites: Bool {
        get { base.skipFavorites }
        set { base.skipFavorites = newValue }
    }

    func reset() { base.reset() }
}
