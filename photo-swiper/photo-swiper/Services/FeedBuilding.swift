import Foundation

/// Turns the library into a session of cards. A Vision-backed version will slot in here.
protocol FeedBuilding: Sendable {
    func makeSession(number: Int, options: FeedOptions) async -> Session
}
