import Foundation

/// Pretends to be a ~17,800 item library that is a fifth of the way reviewed.
struct MockPhotoLibrary: PhotoLibraryProviding {
    var totalItems = 17_820
    var reviewedItems = 3_740
    /// Simulated latency of the system delete prompt.
    var deleteDelay: Duration = .milliseconds(350)

    func stats() async -> LibraryStats {
        LibraryStats(totalItems: totalItems, reviewedItems: reviewedItems, freedBytes: 0)
    }

    func delete(_ items: [LibraryItem]) async throws {
        try await Task.sleep(for: deleteDelay)
    }
}
