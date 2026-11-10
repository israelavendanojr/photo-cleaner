import Foundation

/// Saved progress: per-item decisions, the current deck, and preferences.
///
/// `SwiftDataProgressStore` keeps it on disk; `InMemoryProgressStore` backs mocks, previews, and tests,
/// and is the release fallback when the on-disk store can't be opened.
/// Every mutating call is durable when it returns, so force-quitting never loses work.
@MainActor
protocol ProgressStoring: AnyObject {
    /// Saved decisions for `ids`, from any page.
    func decisions(for ids: Set<LibraryItem.ID>) -> [LibraryItem.ID: StoredDecision]
    /// Writes or replaces decisions. Nil removes one, which undo uses.
    func save(_ changes: [LibraryItem.ID: StoredDecision?])
    /// Marks decided items as settled. Items already settled keep their first settlement.
    func settle(_ ids: Set<LibraryItem.ID>, as settlement: Settlement)
    /// Items settled as gone from the library.
    func goneIDs() -> Set<LibraryItem.ID>
    /// Clears the settlement of items found to be still in the library, so their decision applies
    /// again: a delete is back in the pile. Never deletes anything.
    func reopen(_ ids: Set<LibraryItem.ID>)

    /// Decided delete, not yet settled, oldest decision first.
    func pile() -> [LibraryItem]
    /// Items a new page must not offer. See `StoredDecision.blocksNewSession(asOf:)`.
    func excludedFromNewSession(asOf now: Date) -> Set<LibraryItem.ID>
    /// Items decided keep or delete that are still in the library, each counted once.
    /// "Later" doesn't count, and neither do items settled as deleted or gone.
    func reviewedCount() -> Int
    /// Bytes of items this app actually deleted.
    func freedBytes() -> Int64
    /// The highest page number seen, or 0.
    func lastSessionNumber() -> Int

    /// The current deck.
    func loadSession() -> SavedSession?
    /// Nil clears the saved deck.
    func saveSession(_ saved: SavedSession?)
    /// Writes decisions (as `save` does) and the deck together, in one save where the store can.
    /// Durable when it returns, like every other write. A `.position` write needs this deck already
    /// saved whole under its number; without one nothing is written and it returns false, so the
    /// caller writes `.full` instead.
    @discardableResult
    func commit(_ changes: [LibraryItem.ID: StoredDecision?], deck: DeckWrite) -> Bool

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
    /// Not deleted by this app or gone some other way. Undeletable items are still there.
    var isInLibrary: Bool { settlement != .deleted && settlement != .gone }
}

/// How much of the deck `ProgressStoring.commit` writes.
enum DeckWrite: Equatable, Sendable {
    /// Everything, cards included.
    case full(SavedSession)
    /// Only where the user is in a deck whose cards are already saved: a swipe, a mark, or a draft
    /// leaves the cards as they were, so they aren't encoded again.
    case position(number: Int, index: Int, marks: [SimilarGroup.ID: Set<LibraryItem.ID>], drafts: [FeedCard.ID: [LibraryItem.ID: Decision]])
}

/// The deck, exactly as the user left it.
struct SavedSession: Codable, Equatable, Sendable {
    var session: Session
    var index: Int
    var marks: [SimilarGroup.ID: Set<LibraryItem.ID>]
    /// No longer used: the deck always resumes. Kept so saved rows stay readable; always written false.
    var finished: Bool
    /// Partial one-by-one reviews of batch and similar-shots cards, by card ID.
    /// For a batch that's its batch ID, so drafts saved before this keep loading.
    var drafts: [FeedCard.ID: [LibraryItem.ID: Decision]] = [:]
}
