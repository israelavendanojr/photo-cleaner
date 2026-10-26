import Foundation

/// Picks which items compete for a session, and where each one's features come from.
///
/// Every undecided item with a fresh index record competes on its cached features. The newest
/// `poolSize` undecided items without one compete too, and their metadata gets read live. So the feed
/// works before the index exists and widens to the whole library as the index fills in. Pure, so
/// it's testable without PhotoKit.
enum CandidatePool {
    /// One library item, as the feed's fetch sees it. Favorites state is live, never cached.
    struct Entry: Hashable, Sendable {
        let id: LibraryItem.ID
        let modifiedAt: Date?
        let isFavorite: Bool
    }

    struct Result: Hashable, Sendable {
        /// Indexed items, with cached features.
        var cached: [RankCandidate] = []
        /// Unindexed items, newest first, whose features must be read live.
        var live: [LibraryItem.ID] = []
        /// Fresh records among all `library` entries, excluded ones included.
        var indexedCount = 0
        var totalCount = 0

        /// Index progress for `Session.scanPercentAtStart`, 0...99. Nil once everything is indexed.
        var scanPercent: Int? {
            guard indexedCount < totalCount else { return nil }
            return min(99, indexedCount * 100 / totalCount)
        }
    }

    /// `library` must already be filtered by the user's options (e.g. favorites) and sorted newest first.
    static func build(
        library: [Entry],
        excluding: Set<LibraryItem.ID>,
        indexed: [LibraryItem.ID: IndexedFeatures],
        poolSize: Int,
        version: Int = IndexFreshness.rankableVersion
    ) -> Result {
        var result = Result(totalCount: library.count)
        for entry in library {
            let record = indexed[entry.id].flatMap { record in
                IndexFreshness.isCurrent(record.stamp, assetModifiedAt: entry.modifiedAt, version: version) ? record : nil
            }
            if record != nil { result.indexedCount += 1 }
            guard !excluding.contains(entry.id) else { continue }
            if var features = record?.features {
                features.isFavorite = entry.isFavorite
                result.cached.append(RankCandidate(id: entry.id, features: features))
            } else if result.live.count < poolSize {
                result.live.append(entry.id)
            }
        }
        return result
    }
}
