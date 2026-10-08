import Foundation

/// Access to the user's library. The mock fakes it; a PhotoKit version will slot in here.
protocol PhotoLibraryProviding: Sendable {
    /// Library-wide progress numbers.
    func stats() async -> LibraryStats

    /// Moves items to Recently Deleted. Throws if the user cancels the system prompt.
    func delete(_ items: [LibraryItem]) async throws
}
