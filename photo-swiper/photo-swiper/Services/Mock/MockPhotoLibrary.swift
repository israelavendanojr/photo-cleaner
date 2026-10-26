import Foundation

#if DEBUG
/// Pretends to be a ~17,800 item library that is a fifth of the way reviewed.
struct MockPhotoLibrary: PhotoLibraryProviding {
    var totalItems = 17_820
    var reviewedItems = 3_740
    /// Simulated latency of the system delete prompt.
    var deleteDelay: Duration = .milliseconds(350)
    /// True to act like a fresh install that hasn't been asked for access yet.
    var needsPrompt = false
    /// What the system prompt grants.
    var grantedAccess = LibraryAccess.full

    func needsAccessPrompt() -> Bool {
        needsPrompt
    }

    func requestAccess() async -> LibraryAccess {
        grantedAccess
    }

    func stats() async -> LibraryStats {
        LibraryStats(totalItems: totalItems, reviewedItems: reviewedItems, freedBytes: 0)
    }

    func delete(_ items: [LibraryItem]) async throws -> DeletionOutcome {
        try await Task.sleep(for: deleteDelay)
        return DeletionOutcome(deleted: items.map(\.id))
    }

    func vanishedItems() -> AsyncStream<Set<LibraryItem.ID>> {
        AsyncStream { $0.finish() }
    }

    func missing(from ids: Set<LibraryItem.ID>) async -> Set<LibraryItem.ID> {
        []
    }
}
#endif
