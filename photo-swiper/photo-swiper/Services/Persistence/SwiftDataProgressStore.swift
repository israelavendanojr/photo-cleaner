import Foundation
import OSLog
import SwiftData

/// Progress kept on device with SwiftData. Every mutating call saves before returning.
///
/// A new page's exclusions need every decision, and reading 50,000 rows takes seconds on the main
/// thread. So the first page build reads them once into a small mirror of each decision (its kind,
/// date, and settlement), and every successful save updates it after. The reviewed count, needed on
/// every swipe, reads the mirror once it's there and counts on disk before that, so launch never waits
/// for it. Disk stays the truth: a failed save drops the mirror, and the next page rebuilds it. This
/// store must be the only writer of its rows, which it is in the app.
@MainActor
final class SwiftDataProgressStore: ProgressStoring {
    private static let skipFavoritesKey = "skipFavorites"
    private static let log = Logger.app(category: "progress")

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Nil keeps preferences in memory, for tests.
    private let defaults: UserDefaults?
    private var localSkipFavorites = true
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Nil until first needed, and after a failed save.
    private var mirror: Mirror?

    init(container: ModelContainer, defaults: UserDefaults? = .standard) {
        self.container = container
        self.defaults = defaults
    }

    /// The app's container: the default on-disk store, a store at `url`, or one in memory.
    /// Progress and the feature index share it, so both live in one file. Its models are versioned;
    /// see `BristleSchemaV1` before changing any of them.
    nonisolated static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration = if let url { ModelConfiguration(url: url) } else { ModelConfiguration(isStoredInMemoryOnly: inMemory) }
        return try ModelContainer(
            for: Schema(versionedSchema: BristleSchemaV1.self),
            migrationPlan: BristleMigrationPlan.self,
            configurations: configuration
        )
    }

    /// The app's on-disk store, or one at `url` (tests).
    static func onDisk(url: URL? = nil) throws -> SwiftDataProgressStore {
        SwiftDataProgressStore(container: try makeContainer(url: url))
    }

    /// A throwaway store that never touches disk or `UserDefaults`.
    static func inMemory() throws -> SwiftDataProgressStore {
        SwiftDataProgressStore(container: try makeContainer(inMemory: true), defaults: nil)
    }

    // MARK: Decisions

    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision] {
        Dictionary(records(for: ids).compactMap { record in decision(from: record).map { (record.itemID, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    func save(_ changes: [LibraryItem.ID: StoredDecision?]) {
        guard !changes.isEmpty else { return }
        persist(stage(changes))
    }

    /// Applies decision changes to the context, unsaved. Returns them as the mirror sees them.
    private func stage(_ changes: [LibraryItem.ID: StoredDecision?]) -> [LibraryItem.ID: Mirror.Entry?] {
        guard !changes.isEmpty else { return [:] }
        var staged: [LibraryItem.ID: Mirror.Entry?] = [:]
        let existing = Dictionary(records(for: Set(changes.keys)).map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, change) in changes {
            guard let change else {
                if let record = existing[id] {
                    context.delete(record)
                    staged[id] = .some(nil)
                }
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
            staged[id] = Mirror.Entry(record)
        }
        return staged
    }

    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement) {
        let open = records(for: ids).filter { $0.settlementRaw == nil }
        guard !open.isEmpty else { return }
        var staged: [LibraryItem.ID: Mirror.Entry?] = [:]
        for record in open {
            record.settlementRaw = settlement.rawValue
            record.settledAt = .now
            staged[record.itemID] = Mirror.Entry(record)
        }
        persist(staged)
    }

    func goneIDs() -> Set<LibraryItem.ID> {
        let gone: String? = Settlement.gone.rawValue
        var descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.settlementRaw == gone })
        descriptor.propertiesToFetch = [\.itemID]
        return Set(fetch(descriptor).map(\.itemID))
    }

    func reopen(_ ids: Set<LibraryItem.ID>) {
        let settled = records(for: ids).filter { $0.settlementRaw != nil }
        guard !settled.isEmpty else { return }
        var staged: [LibraryItem.ID: Mirror.Entry?] = [:]
        for record in settled {
            record.settlementRaw = nil
            record.settledAt = nil
            staged[record.itemID] = Mirror.Entry(record)
        }
        persist(staged)
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
        loadedMirror().excluded(asOf: now)
    }

    func reviewedCount() -> Int {
        if let mirror { return mirror.reviewedCount }
        let later = Decision.later.rawValue
        // Rows are unique by item, so each asset counts once. Only undeletable items stay in the library once settled.
        let undeletable: String? = Settlement.undeletable.rawValue
        let descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate {
            $0.decisionRaw != later && ($0.settlementRaw == nil || $0.settlementRaw == undeletable)
        })
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
                drafts: row.drafts.flatMap { try? decoder.decode([FeedCard.ID: [LibraryItem.ID: Decision]].self, from: $0) } ?? [:]
            )
        } catch {
            // Likely an older snapshot format. Decisions are stored separately, so only the card order is lost.
            Self.log.error("Dropping unreadable saved session: \(error)")
            return nil
        }
    }

    func saveSession(_ saved: SavedSession?) {
        stageSession(saved)
        persist()
    }

    @discardableResult
    func commit(_ changes: [LibraryItem.ID: StoredDecision?], deck: DeckWrite) -> Bool {
        switch deck {
        case .full(let saved):
            stageSession(saved)
        case .position(let number, let index, let marks, let drafts):
            // The newest row is the deck `loadSession` resumes; only it may be updated in place.
            guard let row = currentSession(), row.number == number, let marksData = try? encoder.encode(marks) else { return false }
            row.index = index
            row.finished = false
            row.marks = marksData
            row.drafts = try? encoder.encode(drafts)
            row.updatedAt = .now
        }
        persist(stage(changes))
        return true
    }

    /// Applies a deck write to the context, unsaved. Nil clears the saved deck.
    private func stageSession(_ saved: SavedSession?) {
        let rows = fetch(FetchDescriptor<SessionProgress>())
        guard let saved,
              let snapshot = try? encoder.encode(saved.session),
              let marks = try? encoder.encode(saved.marks) else {
            for row in rows { context.delete(row) }
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
        mirror = nil
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

    /// Saves, then brings the mirror up to date with `staged` decision changes (nil: row deleted).
    private func persist(_ staged: [LibraryItem.ID: Mirror.Entry?] = [:]) {
        do {
            try context.save()
            mirror?.apply(staged)
        } catch {
            Self.log.error("Couldn't save progress: \(error)")
            assertionFailure("Couldn't save progress: \(error)")
            mirror = nil
        }
    }

    private func loadedMirror() -> Mirror {
        if let mirror { return mirror }
        var descriptor = FetchDescriptor<ItemProgress>()
        descriptor.propertiesToFetch = [\.itemID, \.decisionRaw, \.decidedAt, \.settlementRaw]
        let loaded = Mirror(fetch(descriptor).map { ($0.itemID, Mirror.Entry($0)) })
        mirror = loaded
        return loaded
    }
}

/// What the reviewed count and a new page's exclusions need of each saved decision.
private struct Mirror {
    struct Entry: Equatable {
        let decisionRaw: String
        let decidedAt: Date
        let settlementRaw: String?

        init(_ record: ItemProgress) {
            decisionRaw = record.decisionRaw
            decidedAt = record.decidedAt
            settlementRaw = record.settlementRaw
        }

        /// The same rule as `StoredDecision`: keep or delete still in the library, each item once.
        /// Only undeletable items stay in the library once settled.
        var isReviewed: Bool {
            decisionRaw != Decision.later.rawValue && (settlementRaw == nil || settlementRaw == Settlement.undeletable.rawValue)
        }
    }

    private var entries: [LibraryItem.ID: Entry] = [:]
    /// Decided anything but "later": never offered again.
    private var blocked: Set<LibraryItem.ID> = []
    private(set) var reviewedCount = 0

    init(_ rows: [(LibraryItem.ID, Entry)]) {
        for (id, entry) in rows { set(id, entry) }
    }

    /// See `StoredDecision.blocksNewSession(asOf:)`: "later" sits out for `laterCooldown`.
    func excluded(asOf now: Date) -> Set<LibraryItem.ID> {
        let cutoff = now.addingTimeInterval(-StoredDecision.laterCooldown)
        var excluded = blocked
        for (id, entry) in entries where entry.decisionRaw == Decision.later.rawValue && entry.decidedAt > cutoff {
            excluded.insert(id)
        }
        return excluded
    }

    mutating func apply(_ changes: [LibraryItem.ID: Entry?]) {
        for (id, entry) in changes { set(id, entry) }
    }

    private mutating func set(_ id: LibraryItem.ID, _ entry: Entry?) {
        if let old = entries[id] {
            if old.isReviewed { reviewedCount -= 1 }
            blocked.remove(id)
        }
        entries[id] = entry
        guard let entry else { return }
        if entry.isReviewed { reviewedCount += 1 }
        if entry.decisionRaw != Decision.later.rawValue { blocked.insert(id) }
    }
}
