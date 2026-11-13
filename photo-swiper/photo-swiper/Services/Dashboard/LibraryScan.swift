import Foundation

/// What's left to look at in the library, for the dashboard's rows: what's left to clear by kind, plus
/// all videos, Live Photos, plain photos, what the image analysis flagged (accidental, blurry, documents)
/// and what was saved for later.
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

    /// Items worth clearing, by kind, plus `.photo`: every undecided plain photo at full size. Apart from
    /// photos, each item is in at most one bucket. Only the extra copies of a
    /// duplicate set and the shots other than the best of a similar set count: those are what clearing frees,
    /// so the number isn't oversold.
    var buckets: [CleanupCategory: Bucket] = [:]
    /// The rows that aren't a cleanup category: every undecided video, every undecided Live Photo, every
    /// undecided photo the analysis flagged, and everything saved for later, each at full size. These overlap the buckets and each other: a large
    /// video is also a video, and a Live Photo can be a similar shot.
    var focusBuckets: [FocusTarget: Bucket] = [:]
    /// Undecided indexed items and their size.
    var indexedCount = 0
    var indexedBytes: Int64 = 0
    /// How far the index has got, 0...100. Nil once it's complete.
    var scanPercent: Int?

    /// The counts behind a row.
    func bucket(for focus: FocusTarget) -> Bucket? {
        if case .category(let category) = focus { return buckets[category] }
        return focusBuckets[focus]
    }

    /// Sorts undecided items into buckets.
    ///
    /// Group members are counted first, so a burst shot in a similar set counts once, as similar.
    /// After that a video counts if it's large, then a screenshot, then a burst shot the user or the
    /// camera didn't pick. Separately, every plain photo (not a video, screenshot or burst shot, as
    /// `CleanupCategory.inferred` reads it) counts as `.photo`, the same test a photo focus uses.
    /// Favorites aren't counted, as the feed skips them.
    /// - Parameters:
    ///   - livePhotos: Live Photo IDs, from the catalog; the index doesn't record them.
    ///   - later: Items saved for later. They're decided, so usually in `excluding`, and counted anyway.
    static func make(
        features: [LibraryItem.ID: AssetFeatures], excluding: Set<LibraryItem.ID>,
        duplicates: [PlannedGroup], similar: [PlannedGroup], scanPercent: Int?,
        livePhotos: Set<LibraryItem.ID> = [], later: Set<LibraryItem.ID> = []
    ) -> LibraryScan {
        var scan = LibraryScan(scanPercent: scanPercent)
        var members: [FocusTarget: [Int64]] = [:]
        var grouped: Set<LibraryItem.ID> = []
        for (category, groups) in [(CleanupCategory.duplicate, duplicates), (.similar, similar)] {
            for group in groups {
                for id in group.ids where id != group.bestID && !excluding.contains(id) && !grouped.contains(id) {
                    guard let bytes = features[id]?.bytes else { continue }
                    grouped.insert(id)
                    members[.category(category), default: []].append(bytes)
                }
            }
        }
        for (id, item) in features where !excluding.contains(id) {
            scan.indexedCount += 1
            scan.indexedBytes += item.bytes
            guard !item.isFavorite else { continue }
            if item.isVideo { members[.allVideos, default: []].append(item.bytes) }
            if livePhotos.contains(id), !item.isVideo { members[.livePhotos, default: []].append(item.bytes) }
            if CleanupCategory.inferred(from: item) == .photo { members[.category(.photo), default: []].append(item.bytes) }
            for focus in findings(item) { members[focus, default: []].append(item.bytes) }
            guard !grouped.contains(id), let category = suggested(item) else { continue }
            members[.category(category), default: []].append(item.bytes)
        }
        for id in later {
            guard let item = features[id] else { continue }
            members[.savedForLater, default: []].append(item.bytes)
        }

        for (focus, sizes) in members {
            var bucket = Bucket()
            for bytes in sizes { bucket.add(bytes) }
            if case .category(let category) = focus {
                scan.buckets[category] = bucket
            } else {
                scan.focusBuckets[focus] = bucket
            }
        }
        return scan
    }

    /// What the image analysis found in a photo: accidental or blurry (never both, as `ImageFlags.classify`
    /// decides), and whether it's a document. Videos and screenshots have no image signals, so nothing.
    static func findings(_ item: AssetFeatures) -> [FocusTarget] {
        guard !item.isVideo, !item.isScreenshot else { return [] }
        var found: [FocusTarget] = []
        switch ImageFlags.classify(item).first {
        case .accidental: found.append(.accidental)
        case .blurry: found.append(.blurry)
        default: break
        }
        if item.isUtility == true { found.append(.documents) }
        return found
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
