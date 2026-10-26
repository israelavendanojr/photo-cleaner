import Foundation

/// Turns the library into a session of cards. A Vision-backed version will slot in here.
protocol FeedBuilding: Sendable {
    func makeSession(number: Int, options: FeedOptions) async -> Session
    /// What's left to clear outside the current session, roughly. Nil when there's nothing to go on.
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate?
}

extension FeedBuilding {
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? { nil }
}
