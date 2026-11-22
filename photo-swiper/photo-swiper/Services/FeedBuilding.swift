import Foundation

/// Turns the library into a session of cards. A Vision-backed version will slot in here.
protocol FeedBuilding: Sendable {
    func makeSession(number: Int, options: FeedOptions) async -> Session
    /// What's left to clear outside the current session, roughly. Nil when there's nothing to go on.
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate?
    /// What's left to look at by kind, for the dashboard's chips, leaving out `excluding` and anything the
    /// last page left out. `removed` are items deleted or gone that the index may still hold; the scan leaves
    /// them out. `later` is what was saved for later, counted for its own chip. Nil when there's nothing to go on yet.
    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>, later: Set<LibraryItem.ID>) async -> LibraryScan?
    /// Every Live Photo in the library, possibly a little stale. Only for items saved before
    /// `LibraryItem.isLivePhoto` existed; new items carry the flag.
    func livePhotoIDs() async -> Set<LibraryItem.ID>
}

extension FeedBuilding {
    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? { nil }
    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>, later: Set<LibraryItem.ID>) async -> LibraryScan? { nil }
    func livePhotoIDs() async -> Set<LibraryItem.ID> { [] }
}
