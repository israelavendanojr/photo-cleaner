import CoreLocation
import CryptoKit
import Foundation
import OSLog
import Photos

/// Builds sessions from the real library, most worth reviewing first.
///
/// `CandidatePool` decides who competes: every undecided item the feature index has fresh features
/// for, plus the newest `poolSize` undecided items it doesn't, whose metadata is read live.
/// `SimilarGrouper` and `BestPick` turn near-identical indexed photos into similar groups.
/// `FeedRanker` scores the rest and `SessionPlanner` takes the top `photosPerSession`, batching
/// screenshots by week. Items in `FeedOptions.excluding`, such as ones already decided, are skipped.
actor PhotoKitFeedBuilder: FeedBuilding {
    static let photosPerSession = 20
    /// How many of the newest unindexed undecided items compete, with metadata read live. Indexed
    /// items compete on cached features and don't count toward it.
    static let poolSize = 500
    /// Fewer screenshots than this in a week show up as ordinary photo cards.
    static let minBatch = 3
    static let maxBatch = 40
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "feed")

    private let index: (any FeatureIndexReading)?
    private let places = PlaceNamer()
    private let grouper = SimilarGrouper()
    private let planner = SessionPlanner(
        limit: PhotoKitFeedBuilder.photosPerSession,
        minBatch: PhotoKitFeedBuilder.minBatch,
        maxBatch: PhotoKitFeedBuilder.maxBatch
    )

    /// Without an index, every candidate is read live, as before the index existed.
    init(index: (any FeatureIndexReading)? = nil) {
        self.index = index
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let started = Date.now
        let pool = await candidatePool(options)
        let similar = await similarGroups(in: pool)
        let slots = planner.plan(pool.candidates, groups: similar.planned, now: .now)

        let chosenIDs = slots.flatMap(\.ids)
        var assets: [LibraryItem.ID: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: chosenIDs, options: nil).enumerateObjects { asset, _, _ in
            assets[asset.localIdentifier] = asset
        }
        let locations = Dictionary(
            assets.compactMap { id, asset in asset.location.map { (id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let names = await places.names(for: locations, within: options.placeBudget)
        let item = { (id: LibraryItem.ID) -> LibraryItem? in
            guard let asset = assets[id], let features = pool.features[id] else { return nil }
            return AssetMapper.item(for: asset, features: features, location: names[id])
        }

        let cards: [FeedCard] = slots.compactMap { slot in
            switch slot {
            case .single(let id):
                return item(id).map(FeedCard.init(item:))
            case .similar(let ids, let bestID, let reason):
                let shots = ids.compactMap(item)
                guard shots.count > 1, shots.contains(where: { $0.id == bestID }) else { return nil }
                return FeedCard.similar(SimilarGroup(
                    id: Self.similarID(shots.map(\.id)), items: shots, bestID: bestID, reason: reason,
                    maxDistance: similar.maxDistance[Self.similarID(ids)]
                ))
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
        Self.log.info("Session \(number): \(pool.cachedCount) cached + \(pool.liveCount) live candidates, index \(pool.scanPercent.map { "\($0)%" } ?? "complete"), \(similar.planned.count) similar groups from \(similar.printCount) prints (\(similar.seconds, format: .fixed(precision: 2))s), built in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2))s")
        return Session(number: number, cards: cards, scanPercentAtStart: pool.scanPercent)
    }

    private struct Pool {
        var candidates: [RankCandidate]
        /// The indexed part of `candidates`. Only these can be grouped: a stale record's print is out of date.
        var cached: [RankCandidate]
        var features: [LibraryItem.ID: AssetFeatures]
        var cachedCount: Int
        var liveCount: Int
        var scanPercent: Int?
    }

    /// Lists the library once for membership, favorites, and edit dates, then reads live metadata
    /// only for the unindexed items that compete.
    private func candidatePool(_ options: FeedOptions) async -> Pool {
        let result = PHAsset.fetchAssets(with: PhotoKitLibrary.fetchOptions(skipFavorites: options.skipFavorites))
        var library: [CandidatePool.Entry] = []
        library.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            library.append(CandidatePool.Entry(id: asset.localIdentifier, modifiedAt: asset.modificationDate, isFavorite: asset.isFavorite))
        }
        let indexed = await index?.indexed() ?? [:]
        let chosen = CandidatePool.build(library: library, excluding: options.excluding, indexed: indexed, poolSize: Self.poolSize)

        var candidates = chosen.cached
        var live: [LibraryItem.ID: AssetFeatures] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: chosen.live, options: nil).enumerateObjects { asset, _, _ in
            live[asset.localIdentifier] = AssetMapper.features(for: asset)
        }
        // Keep newest-first order for the live part.
        candidates += chosen.live.compactMap { id in live[id].map { RankCandidate(id: id, features: $0) } }
        let features = Dictionary(candidates.map { ($0.id, $0.features) }, uniquingKeysWith: { first, _ in first })
        return Pool(candidates: candidates, cached: chosen.cached, features: features, cachedCount: chosen.cached.count,
                    liveCount: live.count, scanPercent: index == nil ? nil : chosen.scanPercent)
    }

    private struct Similar {
        var planned: [PlannedGroup] = []
        /// By `SimilarGroup.id`.
        var maxDistance: [SimilarGroup.ID: Double] = [:]
        var result = SimilarGrouper.Result()
        var printCount = 0
        var seconds = 0.0
    }

    /// Groups indexed photos that have a neighbor in time or a burst. Groups with two or more
    /// favorites are dropped, so those photos compete as singles.
    private func similarGroups(in pool: Pool) async -> Similar {
        guard let index else { return Similar() }
        let started = Date.now
        let neighbors = grouper.neighborIDs(pool.cached)
        let prints = await index.featurePrints(for: Array(neighbors))
        var similar = Similar(result: grouper.group(pool.cached.filter { neighbors.contains($0.id) }, prints: prints), printCount: prints.count)
        for group in similar.result.groups {
            let members = group.ids.compactMap { id in pool.features[id].map { RankCandidate(id: id, features: $0) } }
            guard let choice = BestPick.choose(members) else { continue }
            similar.planned.append(PlannedGroup(ids: group.ids, bestID: choice.bestID, reason: choice.reason.rawValue))
            similar.maxDistance[Self.similarID(group.ids)] = Double(group.maxDistance)
        }
        similar.seconds = Date.now.timeIntervalSince(started)
        return similar
    }

    /// The same members always get the same id, whatever the session, so saved marks keep matching.
    static func similarID(_ ids: [LibraryItem.ID]) -> SimilarGroup.ID {
        let digest = SHA256.hash(data: Data(ids.sorted().joined(separator: "\n").utf8))
        return "similar-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
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
