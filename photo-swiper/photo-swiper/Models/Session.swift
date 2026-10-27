import Foundation

/// The deck: the cards the user swipes through, in order. It grows a page at a time.
struct Session: Identifiable, Hashable, Sendable, Codable {
    /// The newest page in the deck. Pages are numbered across decks; decisions record the page they were made on.
    var number: Int
    /// Upcoming cards can be pruned when items vanish from the library.
    var cards: [FeedCard]
    /// Library analysis still in progress when the deck starts, 0...100. Nil once done.
    var scanPercentAtStart: Int?

    var id: Int { number }

    /// Every item across all cards, in feed order.
    var items: [LibraryItem] { cards.flatMap(\.items) }
    /// Photos across all cards; a bundle counts every item in it.
    var photoCount: Int { cards.reduce(0) { $0 + $1.items.count } }
}

/// Library-wide numbers that live outside the deck.
struct LibraryStats: Sendable {
    var totalItems: Int
    var reviewedItems: Int
    var freedBytes: Int64
}

/// User preferences that shape how feeds are built.
struct FeedOptions: Sendable {
    var skipFavorites = true
    /// Items a page must not offer, e.g. ones already decided or already in the deck.
    var excluding: Set<LibraryItem.ID> = []
    /// How long to wait on place names for captions. Zero skips the lookup.
    var placeBudget: Duration = .milliseconds(1500)
}
