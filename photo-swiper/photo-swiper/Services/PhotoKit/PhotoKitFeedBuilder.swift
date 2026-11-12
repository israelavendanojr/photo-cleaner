import CoreLocation
import Foundation
import OSLog

/// Builds sessions from the real library, most worth reviewing first.
///
/// `CandidatePool` decides who competes: every undecided item the feature index has fresh features
/// for, plus the newest `poolSize` undecided items it doesn't, whose metadata is read live.
/// `DuplicateGrouper` and `DuplicatePick` first find copies of one photo; `SimilarGrouper` and
/// `BestPick` then turn the remaining near-identical indexed photos into similar groups, so a photo
/// is never in both.
/// `FeedRanker` scores the rest and `SessionPlanner` takes the top `photosPerSession`, batching
/// screenshots by week. Items in `FeedOptions.excluding`, such as ones already decided, are skipped.
///
/// The library comes through `catalog` and place names through `geocoder`, so tests build whole
/// pages without PhotoKit or the network.
///
/// The library is listed afresh every page (membership, favorites, and edits change), but the index's
/// records and the grouping work are kept between pages until the index changes; see `GroupingCache`.
actor PhotoKitFeedBuilder: FeedBuilding {
    static let photosPerSession = 20
    /// How many of the newest unindexed undecided items compete, with metadata read live. Indexed
    /// items compete on cached features and don't count toward it.
    static let poolSize = 500
    /// Fewer screenshots than this in a week show up as ordinary photo cards.
    static let minBatch = 3
    static let maxBatch = 40
    private static let log = Logger.app(category: "feed")
    /// Intervals for each stage of a page build, for Instruments' os_signpost track.
    private static let signposter = OSSignposter(logger: log)

    private let index: (any FeatureIndexReading)?
    private let catalog: any AssetCatalog
    private let places: PlaceNamer
    private let grouper = SimilarGrouper()
    private let duplicateGrouper = DuplicateGrouper()
    private let cache: GroupingCache
    /// The index's records at a generation, until it changes.
    private var indexed: (generation: Int, records: [LibraryItem.ID: IndexedFeatures])?
    /// Live Photo IDs at an index generation, for the dashboard.
    private var livePhotos: (generation: Int, ids: Set<LibraryItem.ID>)?
    private let planner = SessionPlanner(
        limit: PhotoKitFeedBuilder.photosPerSession,
        minBatch: PhotoKitFeedBuilder.minBatch,
        maxBatch: PhotoKitFeedBuilder.maxBatch
    )

    /// Without an index, every candidate is read live, as before the index existed.
    /// Similar groups the last session found but didn't show, for the clutter estimate.
    private var similarGroupsLeft = 0
    /// The last page's duplicate and similar sets, for the dashboard's scan. Ids only.
    private var lastGroups: (duplicates: [PlannedGroup], similar: [PlannedGroup]) = ([], [])
    /// How far the index had got when the last page was built. Nil once complete.
    private var lastScanPercent: Int?
    /// What the last page was told to leave out (every decided item, and the deck), for the dashboard's scan.
    private var lastExcluding: Set<LibraryItem.ID> = []

    init(index: (any FeatureIndexReading)? = nil, catalog: any AssetCatalog = PhotoKitAssetCatalog(),
         geocoder: any Geocoding = CLGeocoding()) {
        self.index = index
        self.catalog = catalog
        places = PlaceNamer(geocoder: geocoder)
        cache = GroupingCache(duplicateGrouper: duplicateGrouper, similarGrouper: grouper)
    }

    func clutterEstimate(excluding: Set<LibraryItem.ID>, now: Date) async -> ClutterEstimate? {
        guard let index else { return nil }
        var estimate = await index.clutterEstimate(excluding: excluding, now: now)
        estimate.similarGroupCount = similarGroupsLeft
        return estimate
    }

    /// The index's features plus the last page's groups. Before the first page there are no groups yet,
    /// so duplicates and similar shots show up once the feed has been built. `excluding` adds to what the
    /// last page left out (decided items), so callers only pass what they hold in memory.
    func libraryScan(excluding: Set<LibraryItem.ID>, removed: Set<LibraryItem.ID>) async -> LibraryScan? {
        guard index != nil else { return nil }
        let (generation, records) = await indexedRecords()
        let features = records.mapValues(\.features)
        let decided = excluding.union(lastExcluding)
        var scan = LibraryScan.make(features: features, excluding: decided, duplicates: lastGroups.duplicates,
                                    similar: lastGroups.similar, scanPercent: lastScanPercent)
        scan.profile = LibraryProfile.make(features: features, livePhotos: livePhotoIDs(at: generation), decided: decided,
                                           removed: removed, now: .now)
        return scan
    }

    /// Live Photo IDs, fetched again only when the index has changed: a new Live Photo isn't counted
    /// until it's indexed anyway, and the fetch walks every Live Photo in the library.
    private func livePhotoIDs(at generation: Int) -> Set<LibraryItem.ID> {
        if let livePhotos, livePhotos.generation == generation { return livePhotos.ids }
        let ids = catalog.livePhotoIDs()
        livePhotos = (generation, ids)
        return ids
    }

    func makeSession(number: Int, options: FeedOptions) async -> Session {
        let started = Date.now
        let signposts = Self.signposter
        let build = signposts.beginInterval("makeSession", id: signposts.makeSignpostID(), "page \(number)")
        defer { signposts.endInterval("makeSession", build) }

        let pool = await candidatePool(options)
        let grouping = signposts.beginInterval("grouping")
        let groups = await groups(in: pool, skipFavorites: options.skipFavorites)
        signposts.endInterval("grouping", grouping, "\(groups.duplicatePrintCount + groups.similarPrintCount) prints")
        let planning = signposts.beginInterval("plan")
        let focused = FeedFocus.apply(.init(candidates: pool.candidates, duplicates: groups.duplicates, similar: groups.similar),
                                      focus: options.focus)
        let slots = planner.plan(focused.candidates, groups: focused.similar, duplicates: focused.duplicates, now: .now)
        signposts.endInterval("plan", planning)
        similarGroupsLeft = groups.similar.count - slots.filter(\.isSimilar).count
        lastGroups = (groups.duplicates, groups.similar)
        lastScanPercent = pool.scanPercent
        lastExcluding = options.excluding
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "logSimilarity") { logSimilarity(groups, session: number) }
        #endif

        // Chosen items deleted meanwhile are left out.
        let present = catalog.locations(for: slots.flatMap(\.ids))
        let locations = present.compactMapValues { $0 }
        let placing = signposts.beginInterval("places")
        let names = await places.names(for: locations, within: options.placeBudget)
        signposts.endInterval("places", placing)
        let item = { (id: LibraryItem.ID) -> LibraryItem? in
            guard present.index(forKey: id) != nil, let features = pool.features[id] else { return nil }
            return AssetMapper.item(id: id, features: features, location: names[id])
        }

        let cards: [FeedCard] = slots.compactMap { slot in
            switch slot {
            case .single(let id):
                return item(id).map(FeedCard.init(item:))
            case .similar(let ids, let bestID, let reason):
                let shots = ids.compactMap(item)
                guard shots.count > 1, shots.contains(where: { $0.id == bestID }) else { return nil }
                return FeedCard.similar(SimilarGroup(
                    id: SimilarGroup.stableID(for: shots.map(\.id)), items: shots, bestID: bestID, reason: reason,
                    maxDistance: groups.maxDistance[SimilarGroup.stableID(for: ids)]
                ))
            case .duplicates(let ids, let keepID, let reason):
                let copies = ids.compactMap(item)
                guard copies.count > 1, copies.contains(where: { $0.id == keepID }) else { return nil }
                return FeedCard.duplicates(DuplicateGroup(
                    id: DuplicateGroup.stableID(for: copies.map(\.id)), items: copies, keepID: keepID, reason: reason
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
        Self.log.info("Session \(number): \(pool.cachedCount) cached + \(pool.liveCount) live candidates, index \(pool.scanPercent.map { "\($0)%" } ?? "complete"), \(groups.similar.count) similar groups from \(groups.similarPrintCount) prints (\(groups.similarSeconds, format: .fixed(precision: 2))s), \(groups.duplicates.count) duplicate sets from \(groups.duplicatePrintCount) prints (\(groups.duplicateSeconds, format: .fixed(precision: 2))s), built in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2))s")
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
        /// The index's generation the cached features were read at.
        var generation = 0
    }

    /// Lists the library once for membership, favorites, and edit dates, then reads live metadata
    /// only for the unindexed items that compete.
    private func candidatePool(_ options: FeedOptions) async -> Pool {
        let signposts = Self.signposter
        let enumerating = signposts.beginInterval("enumerate")
        let library = catalog.entries(skipFavorites: options.skipFavorites)
        signposts.endInterval("enumerate", enumerating, "\(library.count) assets")
        let reading = signposts.beginInterval("indexed")
        let (generation, indexed) = await indexedRecords()
        signposts.endInterval("indexed", reading, "\(indexed.count) records")
        let chosen = CandidatePool.build(library: library, excluding: options.excluding, indexed: indexed, poolSize: Self.poolSize)

        var candidates = chosen.cached
        let readingLive = signposts.beginInterval("live")
        let live = catalog.features(for: chosen.live)
        signposts.endInterval("live", readingLive, "\(live.count) assets")
        // Keep newest-first order for the live part.
        candidates += chosen.live.compactMap { id in live[id].map { RankCandidate(id: id, features: $0) } }
        let features = Dictionary(candidates.map { ($0.id, $0.features) }, uniquingKeysWith: { first, _ in first })
        return Pool(candidates: candidates, cached: chosen.cached, features: features, cachedCount: chosen.cached.count,
                    liveCount: live.count, scanPercent: index == nil ? nil : chosen.scanPercent, generation: generation)
    }

    /// Every index record, read again only when the index has changed since the last read.
    private func indexedRecords() async -> (generation: Int, records: [LibraryItem.ID: IndexedFeatures]) {
        guard let index else { return (0, [:]) }
        // The generation first: records read after it are at least that new.
        let generation = await index.generation
        if let indexed, indexed.generation == generation { return indexed }
        let fresh = (generation: generation, records: await index.indexed())
        indexed = fresh
        return fresh
    }

    /// Duplicate sets, then similar groups, among the indexed candidates. Nothing groups without an index.
    private func groups(in pool: Pool, skipFavorites: Bool) async -> PageGroups {
        guard let index else { return PageGroups() }
        let key = GroupingCache.Key(generation: pool.generation, skipFavorites: skipFavorites)
        return await cache.groups(pool.cached, key: key) { ids in await index.featurePrints(for: ids) }
    }

    /// Duplicate sets ready to plan, keeper first. See `PageGrouping.duplicatePlans`.
    static func duplicatePlans(_ candidates: [RankCandidate], prints: [LibraryItem.ID: FeaturePrint],
                               grouper: DuplicateGrouper = DuplicateGrouper()) -> [PlannedGroup] {
        PageGrouping.duplicatePlans(candidates, prints: prints, grouper: grouper)
    }

    /// What similar grouping may use. See `PageGrouping.similarCandidates`.
    static func similarCandidates(_ candidates: [RankCandidate], excluding duplicates: [PlannedGroup]) -> [RankCandidate] {
        PageGrouping.similarCandidates(candidates, excluding: duplicates)
    }

    #if DEBUG
    private static let similarityLog = Logger.app(category: "similar")

    /// `-logSimilarity YES`: every group found and the near misses just past the threshold, for
    /// tuning `SimilarGrouper.Tunables` on a real library.
    private func logSimilarity(_ page: PageGroups, session: Int) {
        let log = Self.similarityLog
        let t = grouper.tunables
        let groups = page.similarResult.groups
        let picks = Dictionary(page.similar.map { (SimilarGroup.stableID(for: $0.ids), $0) }, uniquingKeysWith: { first, _ in first })
        log.info("Session \(session): threshold \(t.maxDistance, format: .fixed(precision: 2)), gap \(Int(t.maxGap))s, span \(Int(t.maxSpan))s; \(page.similarPrintCount) prints, \(groups.count) groups (\(groups.filter(\.isBurst).count) burst), \(groups.count - page.similar.count) dropped for 2+ favorites")
        for (n, group) in groups.enumerated() {
            let pick = picks[SimilarGroup.stableID(for: group.ids)]
            log.info("  group \(n + 1): \(group.ids.count) shots, \(group.isBurst ? "burst" : "time", privacy: .public), span \(group.span, format: .fixed(precision: 1))s, max d \(group.maxDistance, format: .fixed(precision: 3)), best \(pick?.bestID ?? "none (favorites)", privacy: .public) (\(pick?.reason ?? "-", privacy: .public)) of \(group.ids.joined(separator: ", "), privacy: .public)")
        }
        let misses = page.similarResult.nearMisses.sorted { $0.distance < $1.distance }
        log.info("  \(misses.count) near misses up to \(t.maxDistance + t.nearMissMargin, format: .fixed(precision: 2)); closest \(min(misses.count, 50)):")
        for miss in misses.prefix(50) {
            log.info("  near miss d \(miss.distance, format: .fixed(precision: 3)), gap \(miss.gap, format: .fixed(precision: 1))s: \(miss.seed, privacy: .public) ~ \(miss.other, privacy: .public)")
        }
    }
    #endif

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
