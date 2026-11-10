import Foundation

/// Access to the user's library. `MockPhotoLibrary` fakes it; `PhotoKitLibrary` is the real one.
protocol PhotoLibraryProviding: Sendable {
    /// True until the user has answered the system access prompt. Never prompts.
    func needsAccessPrompt() -> Bool

    /// What the user has granted right now. Never prompts. Only `.full` lets "not found" mean "gone":
    /// under `.limited`, anything outside the selection is invisible but may still be in the library.
    func currentAccess() -> LibraryAccess

    /// Asks for read/write access if needed and reports what was granted.
    func requestAccess() async -> LibraryAccess

    /// Library size, plus any reviewed and freed totals the library itself knows about.
    func stats() async -> LibraryStats

    /// Moves items to Recently Deleted. Throws `DeletionError.cancelled` if the user
    /// declines the system prompt; nothing is deleted in that case.
    func delete(_ items: [LibraryItem]) async throws -> DeletionOutcome

    /// IDs of items removed from the library outside the app, as they happen.
    func vanishedItems() -> AsyncStream<Set<LibraryItem.ID>>

    /// Which of `ids` the app can't find. Catches deletes made while the app was closed, but under
    /// limited access it also reports everything outside the selection; see `currentAccess()`.
    func missing(from ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID>

    /// Under limited access, lets the user add photos to what the app can see.
    @MainActor func presentLimitedPicker() async
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

extension DeletionOutcome {
    /// What a delete request reports before anything is deleted: `requested` items the library didn't
    /// find are missing, and found ones the system won't let this app delete are undeletable. The
    /// rest, `deletable`, go to the system prompt; they're `deleted` only once the user confirms.
    /// Order follows `requested` and `found`. Pure, so it's tested without PhotoKit.
    static func make(requested: [LibraryItem.ID], found: [LibraryItem.ID], deletable: Set<LibraryItem.ID>) -> DeletionOutcome {
        let foundIDs = Set(found)
        var outcome = DeletionOutcome()
        outcome.missing = requested.filter { !foundIDs.contains($0) }
        outcome.undeletable = found.filter { !deletable.contains($0) }
        return outcome
    }
}

enum DeletionError: Error {
    /// The user dismissed the system confirmation.
    case cancelled
    case failed(any Error)
}
