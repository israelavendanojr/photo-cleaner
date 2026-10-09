import Foundation

/// Access to the user's library. `MockPhotoLibrary` fakes it; `PhotoKitLibrary` is the real one.
protocol PhotoLibraryProviding: Sendable {
    /// Asks for read/write access if needed and reports what was granted.
    func requestAccess() async -> LibraryAccess

    /// Library size, plus any reviewed and freed totals the library itself knows about.
    func stats() async -> LibraryStats

    /// Moves items to Recently Deleted. Throws `DeletionError.cancelled` if the user
    /// declines the system prompt; nothing is deleted in that case.
    func delete(_ items: [LibraryItem]) async throws -> DeletionOutcome

    /// IDs of items removed from the library outside the app, as they happen.
    func vanishedItems() -> AsyncStream<Set<LibraryItem.ID>>

    /// Which of `ids` are no longer in the library. Catches deletes made while the app was closed.
    func missing(from ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID>
}

enum LibraryAccess: Sendable {
    case full
    /// The user picked a subset of their library.
    case limited
    case denied
}

/// What a confirmed delete actually did, item by item.
struct DeletionOutcome: Sendable {
    /// Moved to Recently Deleted by this request.
    var deleted: [LibraryItem.ID] = []
    /// Already gone from the library before the request ran.
    var missing: [LibraryItem.ID] = []
    /// Still in the library; the system doesn't allow deleting them.
    var undeletable: [LibraryItem.ID] = []
}

enum DeletionError: Error {
    /// The user dismissed the system confirmation.
    case cancelled
    case failed(any Error)
}
