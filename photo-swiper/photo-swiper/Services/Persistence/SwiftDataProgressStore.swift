import Foundation
import OSLog
import SwiftData

/// Progress kept on device with SwiftData. Every mutating call saves before returning.
@MainActor
final class SwiftDataProgressStore: ProgressStoring {
    static let schema: [any PersistentModel.Type] = [ItemProgress.self, SessionProgress.self]
    private static let skipFavoritesKey = "skipFavorites"
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "progress")

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Nil keeps preferences in memory, for tests.
    private let defaults: UserDefaults?
    private var localSkipFavorites = true
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer, defaults: UserDefaults? = .standard) {
        self.container = container
        self.defaults = defaults
    }

    /// The app's on-disk store.
    static func onDisk() throws -> SwiftDataProgressStore {
        SwiftDataProgressStore(container: try ModelContainer(for: Schema(schema)))
    }

    /// A throwaway store that never touches disk or `UserDefaults`.
    static func inMemory() throws -> SwiftDataProgressStore {
        let container = try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return SwiftDataProgressStore(container: container, defaults: nil)
    }

    // MARK: Decisions

    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision] {
        Dictionary(records(for: ids).compactMap { record in decision(from: record).map { (record.itemID, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    func save(_ changes: [LibraryItem.ID: StoredDecision?]) {
        guard !changes.isEmpty else { return }
        let existing = Dictionary(records(for: Set(changes.keys)).map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, change) in changes {
            guard let change else {
                if let record = existing[id] { context.delete(record) }
                continue
            }
            guard let itemData = try? encoder.encode(change.item) else { continue }
            let record = existing[id] ?? {
                let new = ItemProgress(itemID: id, decisionRaw: change.decision.rawValue, decidedAt: change.decidedAt,
                                       sessionNumber: change.sessionNumber, bytes: change.item.bytes, itemData: itemData)
                context.insert(new)
                return new
            }()
            record.decisionRaw = change.decision.rawValue
            record.decidedAt = change.decidedAt
            record.sessionNumber = change.sessionNumber
            record.bytes = change.item.bytes
            record.itemData = itemData
            if record.settlementRaw != change.settlement?.rawValue {
                record.settlementRaw = change.settlement?.rawValue
                record.settledAt = change.settlement == nil ? nil : .now
            }
        }
        persist()
    }

    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        let open = records(for: ids).filter { $0.settlementRaw == nil }
        guard !open.isEmpty else { return }
        for record in open {
            record.settlementRaw = settlement.rawValue
            record.settledAt = .now
        }
        persist()
    }

    // MARK: Derived

    func pile() -> [LibraryItem] {
        let delete = Decision.delete.rawValue
        let descriptor = FetchDescriptor<ItemProgress>(
            predicate: #Predicate { $0.decisionRaw == delete && $0.settlementRaw == nil },
            sortBy: [SortDescriptor(\.decidedAt)]
        )
        return fetch(descriptor).compactMap { try? decoder.decode(LibraryItem.self, from: $0.itemData) }
    }

    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID> {
        let later = Decision.later.rawValue
        let cutoff = now.addingTimeInterval(-StoredDecision.laterCooldown)
        var descriptor = FetchDescriptor<ItemProgress>(
            predicate: #Predicate { $0.decisionRaw != later || $0.decidedAt > cutoff }
        )
        descriptor.propertiesToFetch = [\.itemID]
        return Set(fetch(descriptor).map(\.itemID))
    }

    func reviewedCount() -> Int {
        let later = Decision.later.rawValue
        let descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.decisionRaw != later })
        do {
            return try context.fetchCount(descriptor)
        } catch {
            Self.log.error("Couldn't count reviewed items: \(error)")
            return 0
        }
    }

    func freedBytes() -> Int64 {
        let deleted: String? = Settlement.deleted.rawValue
        var descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.settlementRaw == deleted })
        descriptor.propertiesToFetch = [\.bytes]
        return fetch(descriptor).reduce(0) { $0 + $1.bytes }
    }

    func lastSessionNumber() -> Int {
        var newest = FetchDescriptor<ItemProgress>(sortBy: [SortDescriptor(\.sessionNumber, order: .reverse)])
        newest.fetchLimit = 1
        return max(fetch(newest).first?.sessionNumber ?? 0, currentSession()?.number ?? 0)
    }

    // MARK: Session

    func loadSession() -> SavedSession? {
        guard let row = currentSession() else { return nil }
        do {
            return SavedSession(
                session: try decoder.decode(Session.self, from: row.snapshot),
                index: row.index,
                marks: try decoder.decode([SimilarGroup.ID: Set<LibraryItem.ID>].self, from: row.marks),
                finished: row.finished,
                drafts: row.drafts.flatMap { try? decoder.decode([ItemBatch.ID: [LibraryItem.ID: Decision]].self, from: $0) } ?? [:]
            )
        } catch {
            // Likely an older snapshot format. Decisions are stored separately, so only the card order is lost.
            Self.log.error("Dropping unreadable saved session: \(error)")
            return nil
        }
    }

    func saveSession(_ saved: SavedSession?) {
        let rows = fetch(FetchDescriptor<SessionProgress>())
        guard let saved,
              let snapshot = try? encoder.encode(saved.session),
              let marks = try? encoder.encode(saved.marks) else {
            for row in rows { context.delete(row) }
            persist()
            return
        }
        // Keep one row; a new session number replaces it.
        let row = rows.first { $0.number == saved.session.number }
        for other in rows where other !== row { context.delete(other) }
        if let row {
            row.index = saved.index
            row.finished = saved.finished
            row.marks = marks
            row.drafts = try? encoder.encode(saved.drafts)
            if row.snapshot != snapshot { row.snapshot = snapshot }
            row.updatedAt = .now
        } else {
            let row = SessionProgress(number: saved.session.number, index: saved.index, finished: saved.finished,
                                      startedAt: .now, snapshot: snapshot, marks: marks)
            row.drafts = try? encoder.encode(saved.drafts)
            context.insert(row)
        }
        persist()
    }

    // MARK: Preferences

    var skipFavorites: Bool {
        get {
            guard let defaults else { return localSkipFavorites }
            return defaults.object(forKey: Self.skipFavoritesKey) as? Bool ?? true
        }
        set {
            guard let defaults else { localSkipFavorites = newValue; return }
            defaults.set(newValue, forKey: Self.skipFavoritesKey)
        }
    }

    func reset() {
        do {
            try context.delete(model: ItemProgress.self)
            try context.delete(model: SessionProgress.self)
        } catch {
            Self.log.error("Couldn't reset progress: \(error)")
        }
        persist()
        localSkipFavorites = true
        defaults?.removeObject(forKey: Self.skipFavoritesKey)
    }

    // MARK: Internals

    private func records(for ids: Set<LibraryItem.ID>) -> [ItemProgress] {
        guard !ids.isEmpty else { return [] }
        let list = Array(ids)
        return fetch(FetchDescriptor<ItemProgress>(predicate: #Predicate { list.contains($0.itemID) }))
    }

    private func currentSession() -> SessionProgress? {
        var descriptor = FetchDescriptor<SessionProgress>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func decision(from record: ItemProgress) -> StoredDecision? {
        guard let decision = Decision(rawValue: record.decisionRaw),
              let item = try? decoder.decode(LibraryItem.self, from: record.itemData) else { return nil }
        return StoredDecision(
            decision: decision, decidedAt: record.decidedAt, sessionNumber: record.sessionNumber,
            item: item, settlement: record.settlementRaw.flatMap(Settlement.init(rawValue:))
        )
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.log.error("Couldn't fetch progress: \(error)")
            return []
        }
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            Self.log.error("Couldn't save progress: \(error)")
            assertionFailure("Couldn't save progress: \(error)")
        }
    }
}
