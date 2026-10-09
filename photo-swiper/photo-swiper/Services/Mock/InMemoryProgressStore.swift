import Foundation

/// Progress that lives only as long as the process. Mocks, previews, and tests use it so they
/// never touch saved progress.
@MainActor
final class InMemoryProgressStore: ProgressStoring {
    private var records: [LibraryItem.ID: StoredDecision] = [:]
    private var saved: SavedSession?
    var skipFavorites = true

    nonisolated init() {}

    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision] {
        records.filter { ids.contains($0.key) }
    }

    func save(_ changes: [LibraryItem.ID: StoredDecision?]) {
        for (id, record) in changes { records[id] = record }
    }

    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        for id in ids where records[id]?.settlement == nil {
            records[id]?.settlement = settlement
        }
    }

    func pile() -> [LibraryItem] {
        records.values.filter(\.isPending).sorted { $0.decidedAt < $1.decidedAt }.map(\.item)
    }

    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID> {
        Set(records.filter { $0.value.blocksNewSession(asOf: now) }.keys)
    }

    func reviewedCount() -> Int {
        records.values.filter { $0.decision != .later }.count
    }

    func freedBytes() -> Int64 {
        records.values.filter { $0.settlement == .deleted }.reduce(0) { $0 + $1.item.bytes }
    }

    func lastSessionNumber() -> Int {
        max(saved?.session.number ?? 0, records.values.map(\.sessionNumber).max() ?? 0)
    }

    func loadSession() -> SavedSession? { saved }

    func saveSession(_ saved: SavedSession?) { self.saved = saved }

    func reset() {
        records = [:]
        saved = nil
        skipFavorites = true
    }
}
