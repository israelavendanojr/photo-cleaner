import Foundation
import Testing
@testable import photo_swiper

/// The contract both stores must meet. Each test runs against both.
@MainActor
struct ProgressStoreTests {
    enum Kind: CaseIterable, CustomTestStringConvertible {
        case inMemory, swiftData
        var testDescription: String { self == .inMemory ? "in-memory" : "SwiftData" }
    }

    private func makeStore(_ kind: Kind) throws -> any ProgressStoring {
        switch kind {
        case .inMemory: InMemoryProgressStore()
        case .swiftData: try SwiftDataProgressStore.inMemory()
        }
    }

    private let session = MockFeedBuilder().makeSessionNow(number: 3)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ item: LibraryItem, _ decision: Decision, at date: Date? = nil) -> StoredDecision {
        StoredDecision(decision: decision, decidedAt: date ?? now, sessionNumber: session.number, item: item)
    }

    @Test(arguments: Kind.allCases)
    func savesReplacesAndRemoves(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let item = session.items[0]

        store.save([item.id: record(item, .later)])
        store.save([item.id: record(item, .keep)])
        #expect(store.decisions(for: [item.id])[item.id]?.decision == .keep)
        #expect(store.decisions(for: [item.id])[item.id]?.item == item)

        store.save([item.id: nil])
        #expect(store.decisions(for: [item.id]).isEmpty)
    }

    @Test(arguments: Kind.allCases)
    func pileIsUnsettledDeletesOnly(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let items = Array(session.items.prefix(4))
        store.save([
            items[0].id: record(items[0], .delete, at: now),
            items[1].id: record(items[1], .delete, at: now.addingTimeInterval(1)),
            items[2].id: record(items[2], .keep),
            items[3].id: record(items[3], .delete),
        ])
        store.settle([items[3].id], as: .undeletable)

        #expect(store.pile().map(\.id) == [items[0].id, items[1].id])
    }

    @Test(arguments: Kind.allCases)
    func totalsCountReviewedAndOnlyFreeConfirmedDeletes(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let items = Array(session.items.prefix(4))
        store.save([
            items[0].id: record(items[0], .delete),
            items[1].id: record(items[1], .delete),
            items[2].id: record(items[2], .keep),
            items[3].id: record(items[3], .later),
        ])
        store.settle([items[0].id], as: .deleted)
        store.settle([items[1].id], as: .gone)
        // A later settlement doesn't overwrite the first.
        store.settle([items[0].id], as: .gone)

        #expect(store.reviewedCount() == 3)
        #expect(store.freedBytes() == items[0].bytes)
    }

    @Test(arguments: Kind.allCases)
    func laterItemsSitOutForADay(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let kept = session.items[0], later = session.items[1]
        store.save([kept.id: record(kept, .keep), later.id: record(later, .later)])

        #expect(store.excludedFromNewSession(asOf: now.addingTimeInterval(23 * 3600)) == [kept.id, later.id])
        #expect(store.excludedFromNewSession(asOf: now.addingTimeInterval(25 * 3600)) == [kept.id])
    }

    @Test(arguments: Kind.allCases)
    func sessionRoundTripsAndClears(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let saved = SavedSession(session: session, index: 7, marks: ["g": ["a", "b"]], finished: false)

        store.saveSession(saved)
        #expect(store.loadSession() == saved)
        #expect(store.lastSessionNumber() == session.number)

        var next = saved
        next.index = 8
        next.finished = true
        store.saveSession(next)
        #expect(store.loadSession() == next)

        store.saveSession(nil)
        #expect(store.loadSession() == nil)
    }

    @Test(arguments: Kind.allCases)
    func resetForgetsEverything(_ kind: Kind) throws {
        let store = try makeStore(kind)
        let item = session.items[0]
        store.save([item.id: record(item, .delete)])
        store.saveSession(SavedSession(session: session, index: 1, marks: [:], finished: false))
        store.skipFavorites = false

        store.reset()

        #expect(store.decisions(for: [item.id]).isEmpty)
        #expect(store.pile().isEmpty)
        #expect(store.loadSession() == nil)
        #expect(store.lastSessionNumber() == 0)
        #expect(store.skipFavorites)
    }
}
