import Foundation

/// Chooses which copy of a duplicate set to keep, and says what decided it.
///
/// The user's favorite first, so a favorite is never suggested for clearing; then the copy with the
/// most pixels; then the one saved first. Pure, so tests pin the order.
enum DuplicatePick {
    enum Reason: String, Sendable, CaseIterable {
        case favorite = "Your favorite"
        case resolution = "Highest resolution"
        case earliest = "Saved first"
    }

    struct Choice: Hashable, Sendable {
        let keepID: LibraryItem.ID
        let reason: Reason
    }

    /// Nil for fewer than two copies, or when two or more are favorites: the user marked more than
    /// one copy to keep, so the set isn't offered.
    static func choose(_ members: [RankCandidate]) -> Choice? {
        guard members.count > 1 else { return nil }
        let favorites = members.filter(\.features.isFavorite)
        guard favorites.count < 2 else { return nil }
        if let favorite = favorites.first { return Choice(keepID: favorite.id, reason: .favorite) }

        let ranked = members.sorted { a, b in
            if a.features.pixelCount != b.features.pixelCount { return a.features.pixelCount > b.features.pixelCount }
            if a.features.createdAt != b.features.createdAt { return a.features.createdAt < b.features.createdAt }
            return a.id < b.id
        }
        let winner = ranked[0]
        let reason: Reason = winner.features.pixelCount > ranked[1].features.pixelCount ? .resolution : .earliest
        return Choice(keepID: winner.id, reason: reason)
    }
}
