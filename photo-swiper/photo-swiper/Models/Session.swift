import Foundation

/// A bounded run of cards the user works through before confirming.
struct Session: Identifiable, Hashable, Sendable, Codable {
    let number: Int
    /// Upcoming cards can be pruned when items vanish from the library.
    var cards: [FeedCard]
    /// Library analysis still in progress when the session starts, 0...100. Nil once done.
    var scanPercentAtStart: Int?

    var id: Int { number }

    /// Every item across all cards, in feed order.
    var items: [LibraryItem] { cards.flatMap(\.items) }
    /// Photos across all cards; a bundle counts every item in it.
    var photoCount: Int { cards.reduce(0) { $0 + $1.items.count } }
}

/// Library-wide numbers that live outside any one session.
struct LibraryStats: Sendable {
    var totalItems: Int
    var reviewedItems: Int
    var freedBytes: Int64
}

/// User preferences that shape how feeds are built.
struct FeedOptions: Sendable {
    var skipFavorites = true
    /// Items a session must not offer, e.g. ones already decided.
    var excluding: Set<LibraryItem.ID> = []
}
