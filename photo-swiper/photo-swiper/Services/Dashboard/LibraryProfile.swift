import Foundation

/// The whole library by kind and by month, for the dashboard's composition, timeline, forecast and insights.
///
/// Built from the feature index's cached features, never from PhotoKit, so it's pure. Unlike
/// `LibraryScan`'s buckets it counts every item, decided or not: it describes the library, not what's
/// left to clear. Items not indexed yet aren't counted, nor ones deleted that the index still holds.
struct LibraryProfile: Equatable, Codable, Sendable {
    /// How the library's space breaks down. Each item is one kind, the first that fits in this order.
    enum Kind: String, CaseIterable, Codable, Sendable {
        case video, livePhoto, screenshot, photo
    }

    /// How far back "recently" reaches, for the pace the forecast uses.
    static let recentDays = 90
    /// Dates before this year are a missing date, not a real one.
    static let earliestYear = 1900

    var composition: [Kind: LibraryScan.Bucket] = [:]
    /// Items and bytes by the month they were taken (the month's first day).
    var monthly: [Date: LibraryScan.Bucket] = [:]
    /// Bytes of items taken in the last `recentDays`.
    var addedRecently: Int64 = 0
    /// When the oldest item not yet decided was taken. Nil when everything is decided.
    var oldestUnreviewed: Date?

    var totalBytes: Int64 { composition.values.reduce(0) { $0 + $1.bytes } }

    /// - Parameters:
    ///   - livePhotos: Live Photo IDs, from the catalog; the index doesn't record them.
    ///   - decided: Items already decided, so they aren't "unreviewed".
    ///   - removed: Items deleted or gone. The index drops them later, and under limited access never.
    static func make(
        features: [LibraryItem.ID: AssetFeatures], livePhotos: Set<LibraryItem.ID>, decided: Set<LibraryItem.ID>,
        removed: Set<LibraryItem.ID> = [], now: Date, calendar: Calendar = .current
    ) -> LibraryProfile {
        var profile = LibraryProfile()
        let recent = now.addingTimeInterval(-Double(recentDays) * 86_400)
        for (id, item) in features where !removed.contains(id) {
            profile.composition[kind(of: item, isLive: livePhotos.contains(id)), default: .init()].add(item.bytes)
            // An asset with no date reads as `.distantPast`; it counts in the total but not in any month or year.
            let dated = calendar.component(.year, from: item.createdAt) >= earliestYear
            if dated, let month = calendar.dateInterval(of: .month, for: item.createdAt)?.start {
                profile.monthly[month, default: .init()].add(item.bytes)
            }
            if item.createdAt > recent, item.createdAt <= now { profile.addedRecently += item.bytes }
            if dated, !decided.contains(id), profile.oldestUnreviewed.map({ item.createdAt < $0 }) ?? true {
                profile.oldestUnreviewed = item.createdAt
            }
        }
        return profile
    }

    static func kind(of item: AssetFeatures, isLive: Bool) -> Kind {
        if item.isVideo { return .video }
        if isLive { return .livePhoto }
        if item.isScreenshot { return .screenshot }
        return .photo
    }
}
