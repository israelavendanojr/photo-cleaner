import Foundation

/// The whole library by kind, for the dashboard's composition bar.
///
/// Built from the feature index's cached features, never from PhotoKit, so it's pure. Unlike
/// `LibraryScan`'s buckets it counts every item, decided or not: it describes the library, not what's
/// left to clear. Items not indexed yet aren't counted, nor ones deleted that the index still holds.
struct LibraryProfile: Equatable, Codable, Sendable {
    /// How the library's space breaks down. Each item is one kind, the first that fits in this order.
    enum Kind: String, CaseIterable, Codable, Sendable {
        case video, livePhoto, screenshot, photo
    }

    var composition: [Kind: LibraryScan.Bucket] = [:]

    var totalBytes: Int64 { composition.values.reduce(0) { $0 + $1.bytes } }

    /// - Parameters:
    ///   - livePhotos: Live Photo IDs, from the catalog; the index doesn't record them.
    ///   - removed: Items deleted or gone. The index drops them later, and under limited access never.
    static func make(
        features: [LibraryItem.ID: AssetFeatures], livePhotos: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID> = []
    ) -> LibraryProfile {
        var profile = LibraryProfile()
        for (id, item) in features where !removed.contains(id) {
            profile.composition[kind(of: item, isLive: livePhotos.contains(id)), default: .init()].add(item.bytes)
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
