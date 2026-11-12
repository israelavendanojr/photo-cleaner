import Foundation

/// What's left to clear in the library, by kind, for the dashboard's suggestions and health score.
///
/// Counted from the feature index's cached features and the last page's grouping, never from PhotoKit,
/// so it's cheap and pure. Items not indexed yet aren't counted, so it's a lower bound while the index
/// is still being built (`scanPercent`).
struct LibraryScan: Equatable, Codable, Sendable {
    /// Videos at least this big are worth a look on their own.
    static let largeVideoBytes: Int64 = 50_000_000

    struct Bucket: Equatable, Codable, Sendable {
        var count = 0
        var bytes: Int64 = 0

        mutating func add(_ bytes: Int64) {
            count += 1
            self.bytes += bytes
        }
    }

    /// Items worth clearing, by kind. Each item is in at most one bucket. Only the extra copies of a
    /// duplicate set and the shots other than the best of a similar set count: those are what clearing frees.
    var buckets: [CleanupCategory: Bucket] = [:]
    /// Undecided indexed items and their size, the base the health score is measured against.
    var indexedCount = 0
    var indexedBytes: Int64 = 0
    /// How far the index has got, 0...100. Nil once it's complete.
    var scanPercent: Int?
    /// The whole library by kind and month. Nil where the builder can't see the library (tests).
    var profile: LibraryProfile?

    /// Sorts undecided items into buckets.
    ///
    /// Group members are counted first, so a burst shot in a similar set counts once, as similar.
    /// After that a video counts if it's large, then a screenshot, then a burst shot the user or the
    /// camera didn't pick.
    static func make(
        features: [LibraryItem.ID: AssetFeatures], excluding: Set<LibraryItem.ID>,
        duplicates: [PlannedGroup], similar: [PlannedGroup], scanPercent: Int?
    ) -> LibraryScan {
        var scan = LibraryScan(scanPercent: scanPercent)
        var grouped: Set<LibraryItem.ID> = []
        for (category, groups) in [(CleanupCategory.duplicate, duplicates), (.similar, similar)] {
            for group in groups {
                for id in group.ids where id != group.bestID && !excluding.contains(id) && !grouped.contains(id) {
                    guard let bytes = features[id]?.bytes else { continue }
                    grouped.insert(id)
                    scan.buckets[category, default: Bucket()].add(bytes)
                }
            }
        }
        for (id, item) in features where !excluding.contains(id) {
            scan.indexedCount += 1
            scan.indexedBytes += item.bytes
            guard !grouped.contains(id), !item.isFavorite, let category = suggested(item) else { continue }
            scan.buckets[category, default: Bucket()].add(item.bytes)
        }
        return scan
    }

    /// The kind a single item is suggested as, if any: a large video, a screenshot, or a burst shot the
    /// user or the camera didn't pick. A focused feed offers exactly these (`FeedFocus`), so a suggestion
    /// leads to what it counted.
    static func suggested(_ item: AssetFeatures) -> CleanupCategory? {
        if item.isVideo { return item.bytes >= largeVideoBytes ? .video : nil }
        if item.isScreenshot { return .screenshot }
        if item.isInBurst, !item.isBurstPick, item.isUserBurstPick != true { return .burst }
        return nil
    }
}
