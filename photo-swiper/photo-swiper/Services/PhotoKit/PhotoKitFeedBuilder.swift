import CoreLocation
import Foundation
import Photos

/// Builds sessions from the real library, most worth reviewing first.
///
/// The newest `poolSize` undecided items compete; `FeedRanker` scores them from metadata and
/// `SessionPlanner` takes the top `photosPerSession`, batching screenshots by week. Similar shots and
/// blur/accidental flags need image analysis and come later. Items in `FeedOptions.excluding`, such
/// as ones already decided, are skipped.
actor PhotoKitFeedBuilder: FeedBuilding {
    static let photosPerSession = 20
    /// How many of the newest undecided items compete for a session. Sizes are read live, so this
    /// stays bounded until a background index caches features for the whole library.
    static let poolSize = 500
    /// Fewer screenshots than this in a week show up as ordinary photo cards.
    static let minBatch = 3
    static let maxBatch = 40

    private let places = PlaceNamer()
    private let planner = SessionPlanner(
        limit: PhotoKitFeedBuilder.photosPerSession,
        minBatch: PhotoKitFeedBuilder.minBatch,
        maxBatch: PhotoKitFeedBuilder.maxBatch
    )

    private struct Entry {
        let asset: PHAsset
        let features: AssetFeatures
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let pool = candidatePool(options)
        let byID = Dictionary(pool.map { ($0.asset.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = planner.plan(
            pool.map { RankCandidate(id: $0.asset.localIdentifier, features: $0.features) },
            now: .now
        )

        let chosen = slots.flatMap(\.ids).compactMap { byID[$0] }
        let locations = Dictionary(
            chosen.compactMap { entry in entry.asset.location.map { (entry.asset.localIdentifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let names = await places.names(for: locations, within: .milliseconds(1500))
        let item = { (id: LibraryItem.ID) -> LibraryItem? in
            byID[id].map { AssetMapper.item(for: $0.asset, features: $0.features, location: names[id]) }
        }

        let cards: [FeedCard] = slots.compactMap { slot in
            switch slot {
            case .single(let id):
                return item(id).map(FeedCard.init(item:))
            case .screenshots(let week, let ids):
                let shots = ids.compactMap(item)
                guard !shots.isEmpty else { return nil }
                return FeedCard.batch(ItemBatch(
                    id: "s\(number)-shots-\(Int(week.timeIntervalSince1970))",
                    kind: .screenshots,
                    label: "Screenshots",
                    title: "\(shots.count) screenshots from \(Self.phrase(forWeek: week))",
                    items: shots
                ))
            }
        }
        return Session(number: number, cards: cards, scanPercentAtStart: nil)
    }

    /// The newest `poolSize` undecided items with their features.
    private func candidatePool(_ options: FeedOptions) -> [Entry] {
        let result = PHAsset.fetchAssets(with: PhotoKitLibrary.fetchOptions(skipFavorites: options.skipFavorites))
        var pool: [Entry] = []
        pool.reserveCapacity(min(Self.poolSize, result.count))
        var index = 0
        while index < result.count, pool.count < Self.poolSize {
            let asset = result.object(at: index)
            index += 1
            guard !options.excluding.contains(asset.localIdentifier) else { continue }
            pool.append(Entry(asset: asset, features: AssetMapper.features(for: asset)))
        }
        return pool
    }

    /// "this week", "last week", or "the week of Sep 22".
    private static func phrase(forWeek week: Date) -> String {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        if calendar.isDate(week, inSameDayAs: thisWeek) { return "this week" }
        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek),
           calendar.isDate(week, inSameDayAs: lastWeek) {
            return "last week"
        }
        return "the week of \(Format.shortDay(week))"
    }
}
