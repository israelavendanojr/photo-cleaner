import Foundation

/// What the user decided for a single item.
enum Decision: String, Hashable, Sendable, Codable {
    /// Pending deletion; nothing is removed until the session is confirmed.
    case delete
    case keep
    case later
}

/// The gesture vocabulary of the feed.
enum SwipeDirection: Hashable, Sendable, CaseIterable {
    /// Delete (or clear the marked part of a group).
    case left
    /// Keep.
    case right
    /// Decide later.
    case up
}
