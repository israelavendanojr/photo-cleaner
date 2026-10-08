import Foundation

/// A bounded run of cards the user works through before confirming.
struct Session: Identifiable, Sendable {
    let number: Int
    /// Upcoming cards can be pruned when items vanish from the library.
    var cards: [FeedCard]
    /// Library analysis still in progress when the session starts, 0...100. Nil once done.
    var scanPercentAtStart: Int?

    var id: Int { number }

    /// Every item across all cards, in feed order.
    var items: [LibraryItem] { cards.flatMap(\.items) }
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
}
