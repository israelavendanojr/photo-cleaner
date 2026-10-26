import Foundation

/// Saved progress: per-item decisions, the current deck, and preferences.
///
/// `SwiftDataProgressStore` keeps it on disk; `InMemoryProgressStore` backs mocks, previews, and tests.
/// Every mutating call is durable when it returns, so force-quitting never loses work.
@MainActor
protocol ProgressStoring: AnyObject {
    /// Saved decisions for `ids`, from any page.
    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision]
    /// Writes or replaces decisions. Nil removes one, which undo uses.
    func save(_ changes: [LibraryItem.ID: StoredDecision?])
    /// Marks decided items as settled. Items already settled keep their first settlement.
    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement)

    /// Decided delete, not yet settled, oldest decision first.
    func pile() -> [LibraryItem]
    /// Items a new page must not offer. See `StoredDecision.blocksNewSession(asOf:)`.
    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID>
    /// Items decided keep or delete. "Later" doesn't count.
    func reviewedCount() -> Int
    /// Bytes of items this app actually deleted.
    func freedBytes() -> Int64
    /// The highest page number seen, or 0.
    func lastSessionNumber() -> Int

    /// The current deck.
    func loadSession() -> SavedSession?
    /// Nil clears the saved deck.
    func saveSession(_ saved: SavedSession?)

    var skipFavorites: Bool { get set }

    /// Forgets everything, including preferences.
    func reset()
}

/// How a pending delete left the pile.
enum Settlement: String, Codable, Sendable {
    /// Deleted by this app.
    case deleted
    /// Gone from the library some other way.
    case gone
    /// The system wouldn't let this app delete it.
    case undeletable
}

/// One item's saved decision.
struct StoredDecision: Equatable, Sendable {
    /// How long a "later" item sits out before a new page may offer it again.
    static let laterCooldown: TimeInterval = 24 * 60 * 60

    var decision: Decision
    var decidedAt: Date
    /// The page the decision was made on.
    var sessionNumber: Int
    /// Metadata only, enough to show the item in the pile. No pixels.
    var item: LibraryItem
    /// Nil while the decision is still open.
    var settlement: Settlement?

    /// Keep and delete are final; "later" sits out for `laterCooldown`.
    func blocksNewSession(asOf now: Date) -> Bool {
        decision != .later || now.timeIntervalSince(decidedAt) < Self.laterCooldown
    }

    var isPending: Bool { decision == .delete && settlement == nil }
}

/// The deck, exactly as the user left it.
struct SavedSession: Codable, Equatable, Sendable {
    var session: Session
    var index: Int
    var marks: [SimilarGroup.ID: Set<LibraryItem.ID>]
    /// No longer used: the deck always resumes. Kept so saved rows stay readable; always written false.
    var finished: Bool
    /// Partial one-by-one reviews of batch cards, by batch.
    var drafts: [ItemBatch.ID: [LibraryItem.ID: Decision]] = [:]
}
