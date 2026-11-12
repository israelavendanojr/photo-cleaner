import Foundation

/// Progress that lives only as long as the process. Mocks, previews, and tests use it so they
/// never touch saved progress.
@MainActor
final class InMemoryProgressStore: ProgressStoring {
    private var records: [LibraryItem.ID: StoredDecision] = [:]
    private var saved: SavedSession?
    private var history: [CleanupEntry] = []
    /// When each item was settled, for the history's backfill.
    private var settledAt: [LibraryItem.ID: Date] = [:]
    private var historyChecked = false
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
            settledAt[id] = .now
        }
    }

    func goneIDs() -> Set<LibraryItem.ID> {
        Set(records.filter { $0.value.settlement == .gone }.keys)
    }

    func reopen(_ ids: Set<LibraryItem.ID>) {
        for id in ids {
            records[id]?.settlement = nil
            settledAt[id] = nil
        }
    }

    func pile() -> [LibraryItem] {
        records.values.filter(\.isPending).sorted { $0.decidedAt < $1.decidedAt }.map(\.item)
    }

    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID> {
        Set(records.filter { $0.value.blocksNewSession(asOf: now) }.keys)
    }

    func reviewedCount() -> Int {
        records.values.filter { $0.decision != .later && $0.isInLibrary }.count
    }

    func reviewsByDay(since: Date, calendar: Calendar) -> [Date: Int] {
        let reviewed = records.values.filter { $0.decision != .later && $0.decidedAt >= since }
        var days = Dictionary(grouping: reviewed) { calendar.startOfDay(for: $0.decidedAt) }.mapValues(\.count)
        #if DEBUG
        for date in debugReviews where date >= since { days[calendar.startOfDay(for: date), default: 0] += 1 }
        #endif
        return days
    }

    #if DEBUG
    /// Made-up review times for the heatmap (`-mockHistory YES`), with no decisions behind them.
    var debugReviews: [Date] = []
    #endif

    func freedBytes() -> Int64 {
        records.values.filter { $0.settlement == .deleted }.reduce(0) { $0 + $1.item.bytes }
    }

    func recordCleanup(_ entries: [CleanupEntry]) {
        guard !entries.isEmpty else { return }
        backfillHistoryIfNeeded()
        history += entries
    }

    func cleanupHistory() -> [CleanupEntry] {
        backfillHistoryIfNeeded()
        return history.sorted { $0.at < $1.at }
    }

    /// The same once-only fill as `SwiftDataProgressStore`'s.
    private func backfillHistoryIfNeeded() {
        guard !historyChecked else { return }
        historyChecked = true
        guard history.isEmpty else { return }
        let settled = records.filter { $0.value.settlement == .deleted }.map { id, record in
            (settledAt[id] ?? record.decidedAt, record.item, record.category ?? .inferred(from: record.item))
        }
        history = CleanupEntry.backfilled(from: settled)
    }

    func lastSessionNumber() -> Int {
        max(saved?.session.number ?? 0, records.values.map(\.sessionNumber).max() ?? 0)
    }

    func loadSession() -> SavedSession? { saved }

    func saveSession(_ saved: SavedSession?) { self.saved = saved }

    @discardableResult
    func commit(_ changes: [LibraryItem.ID: StoredDecision?], deck: DeckWrite) -> Bool {
        switch deck {
        case .full(let next):
            saved = next
        case .position(let number, let index, let marks, let drafts):
            guard var current = saved, current.session.number == number else { return false }
            current.index = index
            current.marks = marks
            current.drafts = drafts
            current.finished = false
            saved = current
        }
        save(changes)
        return true
    }

    func reset() {
        records = [:]
        saved = nil
        history = []
        settledAt = [:]
        historyChecked = false
        skipFavorites = true
    }
}
