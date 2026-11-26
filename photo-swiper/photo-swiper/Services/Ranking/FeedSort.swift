import Foundation

/// The order the feed deals in (JUN-125): Recommended is the ranker's, the others are plain orders the user
/// picks from the sort pill. It combines with `FocusTarget`, e.g. the oldest videos. Not saved: a relaunch
/// shows Recommended.
///
/// Every sort but Recommended is a plain order, so `SessionPlanner` skips its engagement arranging and the
/// feed skips `FrontLoad` under one. Pure, like the rest of `Ranking/`.
enum FeedSort: String, CaseIterable, Identifiable, Sendable {
    /// `FeedRanker` and `SessionPlanner`, as before there was a sort.
    case recommended
    /// Date taken, newest first.
    case newest
    /// Date taken, oldest first.
    case oldest
    /// Total storage, biggest first. A Live Photo's video and an edited render count (`FileSizeReader`).
    case largest

    var id: Self { self }

    /// One card or slot's place in a sort: what it would free, and its members' dates.
    struct Key: Equatable, Sendable {
        /// Every member's bytes together.
        var bytes: Int64
        /// The newest and oldest members with a date. Nil when no member has one.
        var newest: Date?
        var oldest: Date?
        /// Breaks ties, so the order is the same every time.
        var id: String

        /// An item without a creation or modification date reads `.distantPast` (`AssetMapper`); it has no date here.
        init(id: String, members: [(bytes: Int64, date: Date)]) {
            self.id = id
            bytes = members.reduce(0) { $0 + $1.bytes }
            let dated = members.map(\.date).filter { $0 != .distantPast }
            newest = dated.max()
            oldest = dated.min()
        }
    }

    /// Whether something with `key` shows under this sort. Newest and Oldest leave out what has no date;
    /// Recommended and Largest show it.
    func includes(_ key: Key) -> Bool {
        switch self {
        case .recommended, .largest: true
        case .newest: key.newest != nil
        case .oldest: key.oldest != nil
        }
    }

    /// Whether `a` comes before `b`. Largest breaks ties newer first, then by ID; the dates by ID.
    /// Recommended has no order of its own here, so only IDs count.
    func precedes(_ a: Key, _ b: Key) -> Bool {
        switch self {
        case .largest:
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            let (x, y) = (a.newest ?? .distantPast, b.newest ?? .distantPast)
            if x != y { return x > y }
        case .newest:
            if a.newest != b.newest { return (a.newest ?? .distantPast) > (b.newest ?? .distantPast) }
        case .oldest:
            if a.oldest != b.oldest { return (a.oldest ?? .distantFuture) < (b.oldest ?? .distantFuture) }
        case .recommended:
            break
        }
        return a.id < b.id
    }

    /// `cards` in this order, leaving out what it doesn't show. Recommended leaves them as they are. For
    /// builders that deal whole cards, like the mock library; the real feed sorts in `SessionPlanner`.
    func ordered(_ cards: [FeedCard]) -> [FeedCard] {
        guard self != .recommended else { return cards }
        return cards
            .map { ($0, Key(id: $0.id, members: $0.items.map { ($0.bytes, $0.date) })) }
            .filter { includes($0.1) }
            .sorted { precedes($0.1, $1.1) }
            .map(\.0)
    }
}
