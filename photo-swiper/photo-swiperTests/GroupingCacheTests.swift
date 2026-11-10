import Foundation
import Testing
@testable import photo_swiper

/// `GroupingCache` must give exactly what `PageGrouping.uncached` gives, page after page, while
/// reading far fewer prints (JUN-45, Q-1).
struct GroupingCacheTests {
    private let planner = SessionPlanner(limit: PhotoKitFeedBuilder.photosPerSession, minBatch: PhotoKitFeedBuilder.minBatch,
                                         maxBatch: PhotoKitFeedBuilder.maxBatch)

    private func reference(_ cached: [RankCandidate], _ library: SyntheticLibrary) async -> PageGroups {
        await PageGrouping.uncached(cached) { ids in library.prints(for: ids) }
    }

    private func expectSame(_ a: PageGroups, _ b: PageGroups, _ cached: [RankCandidate], page: Int,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.duplicates == b.duplicates, "duplicates differ on page \(page)", sourceLocation: sourceLocation)
        #expect(a.similar == b.similar, "similar groups differ on page \(page)", sourceLocation: sourceLocation)
        #expect(a.maxDistance == b.maxDistance, "distances differ on page \(page)", sourceLocation: sourceLocation)
        #expect(a.similarResult.groups == b.similarResult.groups, "raw groups differ on page \(page)", sourceLocation: sourceLocation)
        #expect(Set(a.similarResult.nearMisses) == Set(b.similarResult.nearMisses), "near misses differ on page \(page)", sourceLocation: sourceLocation)
        let slotsA = planner.plan(cached, groups: a.similar, duplicates: a.duplicates, now: PageRun.now)
        let slotsB = planner.plan(cached, groups: b.similar, duplicates: b.duplicates, now: PageRun.now)
        #expect(slotsA == slotsB, "slots differ on page \(page)", sourceLocation: sourceLocation)
    }

    @Test(arguments: [1, 2, 3, 4] as [UInt64])
    func aWarmCacheMatchesUncachedPageAfterPage(seed: UInt64) async {
        let library = SyntheticLibrary(count: 3_000, seed: seed, dimensions: 32)
        let warm = GroupingCache()
        let key = GroupingCache.Key(generation: 1, skipFavorites: true)
        var excluded: Set<LibraryItem.ID> = []
        var rng = SplitMix64(seed: seed)
        var groupedSomething = false

        for page in 1...10 {
            let cached = library.candidates.filter { !excluded.contains($0.id) }
            let expected = await reference(cached, library)
            let fromWarm = await warm.groups(cached, key: key) { ids in library.prints(for: ids) }
            let fromCold = await GroupingCache().groups(cached, key: key) { ids in library.prints(for: ids) }
            expectSame(fromWarm, expected, cached, page: page)
            expectSame(fromCold, expected, cached, page: page)
            groupedSomething = groupedSomething || (!expected.similar.isEmpty && !expected.duplicates.isEmpty)

            // The page's items are dealt; some single members of groups get decided too, which
            // splits their groups; and on page 6 a few "later" items come back from their cooldown.
            let slots = planner.plan(cached, groups: expected.similar, duplicates: expected.duplicates, now: PageRun.now)
            excluded.formUnion(slots.flatMap(\.ids))
            for group in expected.similar.prefix(10) + expected.duplicates.prefix(5) {
                excluded.insert(group.ids[Int(rng.next() % UInt64(group.ids.count))])
            }
            if page == 6 { excluded.subtract(excluded.shuffled(using: &rng).prefix(30)) }
        }
        #expect(groupedSomething)
    }

    @Test func favoritesAreReadLiveWithoutForgettingGroups() async {
        let library = SyntheticLibrary(count: 3_000, seed: 7, dimensions: 32)
        let cache = GroupingCache()
        let key = GroupingCache.Key(generation: 1, skipFavorites: false)
        let first = await cache.groups(library.candidates) { ids in library.prints(for: ids) }

        // Favorite two members of some groups: those groups must drop out, with nothing reloaded.
        let favorites = Set((first.similar.prefix(3) + first.duplicates.prefix(2)).flatMap { $0.ids.prefix(2) })
        let cached = library.candidates.map { candidate in
            var features = candidate.features
            features.isFavorite = favorites.contains(candidate.id)
            return RankCandidate(id: candidate.id, features: features)
        }
        let loads = PrintLoads(library: library)
        let again = await cache.groups(cached, key: key) { ids in await loads.load(ids) }
        let expected = await reference(cached, library)
        expectSame(again, expected, cached, page: 2)
        #expect(again.similar.count < first.similar.count)
    }

    @Test func aNewGenerationForgetsEverything() async {
        let library = SyntheticLibrary(count: 2_000, seed: 3, dimensions: 32)
        let cache = GroupingCache()
        _ = await cache.groups(library.candidates, key: .init(generation: 1, skipFavorites: true)) { ids in library.prints(for: ids) }

        // The index re-analyzed everything: shots moved in time, so every component changed meaning.
        let moved = library.candidates.map { candidate in
            var features = candidate.features
            features.createdAt = features.createdAt.addingTimeInterval(features.burstID == nil ? Double(candidate.id.utf8.reduce(0) { $0 &+ Int($1) } % 200) : 0)
            return RankCandidate(id: candidate.id, features: features)
        }
        let loads = PrintLoads(library: library)
        let after = await cache.groups(moved, key: .init(generation: 2, skipFavorites: true)) { ids in await loads.load(ids) }
        let cold = await GroupingCache().groups(moved, key: .init(generation: 2, skipFavorites: true)) { ids in library.prints(for: ids) }
        expectSame(after, await reference(moved, library), moved, page: 2)
        #expect(after.similarPrintCount == cold.similarPrintCount)
        #expect(after.duplicatePrintCount == cold.duplicatePrintCount)
    }

    @Test func skippingFavoritesDifferentlyForgetsEverything() async {
        let library = SyntheticLibrary(count: 2_000, seed: 5, dimensions: 32)
        let cache = GroupingCache()
        let first = await cache.groups(library.candidates, key: .init(generation: 1, skipFavorites: true)) { ids in library.prints(for: ids) }
        let again = await cache.groups(library.candidates, key: .init(generation: 1, skipFavorites: true)) { ids in library.prints(for: ids) }
        let switched = await cache.groups(library.candidates, key: .init(generation: 1, skipFavorites: false)) { ids in library.prints(for: ids) }
        #expect(again.similarPrintCount == 0)
        #expect(again.duplicatePrintCount == 0)
        #expect(switched.similarPrintCount == first.similarPrintCount)
        #expect(switched.duplicatePrintCount == first.duplicatePrintCount)
    }

    @Test func laterPagesReadOnlyThePrintsOfWhatChanged() async {
        let library = SyntheticLibrary(count: 5_000, seed: 11, dimensions: 32)
        let cache = GroupingCache()
        let key = GroupingCache.Key(generation: 1, skipFavorites: true)
        let pages = await PageRun.run(library.candidates, pages: 4) { cached in
            await cache.groups(cached, key: key) { ids in library.prints(for: ids) }
        }
        let first = pages[0].printsLoaded
        #expect(first > 0)
        for page in pages.dropFirst() {
            #expect(page.printsLoaded * 10 < first, "page \(page.number) read \(page.printsLoaded) prints, the first \(first)")
        }
    }

    // MARK: The splits the cache relies on

    @Test(arguments: [1, 2, 3] as [UInt64])
    func groupingEachComponentAloneGroupsTheSameAsAll(seed: UInt64) {
        let library = SyntheticLibrary(count: 3_000, seed: seed, dimensions: 32)
        let grouper = SimilarGrouper()
        let neighbors = grouper.neighborIDs(library.candidates)
        let prints = library.prints(for: Array(neighbors))
        let whole = grouper.group(library.candidates.filter { neighbors.contains($0.id) }, prints: prints)
        let parts = grouper.components(library.candidates)
        let merged = grouper.merge(parts.map { grouper.group($0, prints: prints) }, of: library.candidates)

        #expect(Set(parts.flatMap { $0.map(\.id) }) == neighbors)
        #expect(merged.groups == whole.groups)
        #expect(Set(merged.nearMisses) == Set(whole.nearMisses))
        #expect(parts.count > 1)
    }

    @Test func aBurstSpanningAGapStaysInOneComponent() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func shot(_ id: String, _ seconds: TimeInterval, burst: String? = nil) -> RankCandidate {
            RankCandidate(id: id, features: AssetFeatures(createdAt: base.addingTimeInterval(seconds), bytes: 1, burstID: burst, isUtility: false))
        }
        let shots = [shot("a", 0, burst: "b"), shot("b", 10), shot("c", 1_000), shot("d", 1_010), shot("e", 5_000, burst: "b")]
        #expect(SimilarGrouper().components(shots).map { $0.map(\.id) } == [["a", "b", "e"], ["c", "d"]])
    }

    @Test(arguments: [1, 2, 3] as [UInt64])
    func duplicatesFromRememberedDistancesMatchFromPrints(seed: UInt64) {
        let library = SyntheticLibrary(count: 5_000, seed: seed, dimensions: 32)
        let grouper = DuplicateGrouper()
        let paired = grouper.candidateIDs(library.candidates)
        let candidates = library.candidates.filter { paired.contains($0.id) }
        let prints = library.prints(for: candidates.map(\.id))
        let fromPrints = grouper.group(candidates, prints: prints)
        let fromDistances = grouper.group(candidates, hasPrint: { prints[$0] != nil }) { a, b in
            grouper.distance(prints[a]!, prints[b]!)
        }
        #expect(fromDistances == fromPrints)
        #expect(!fromPrints.isEmpty)
    }

    // MARK: Index generation

    @Test func everyIndexWriteBumpsTheGeneration() async throws {
        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
        let features = AssetFeatures(createdAt: .now, bytes: 1)
        let start = await index.generation
        await index.upsert([IndexEntry(id: "a", features: features, modifiedAt: nil, version: 2, indexedAt: .now)])
        let afterUpsert = await index.generation
        await index.updateHashes([HashEntry(id: "a", pixelWidth: 4, pixelHeight: 3, dHash: 1, version: DHash.version)])
        let afterHashes = await index.generation
        await index.remove(["a"])
        let afterRemove = await index.generation
        await index.upsert([])
        await index.remove([])

        #expect(start < afterUpsert)
        #expect(afterUpsert < afterHashes)
        #expect(afterHashes < afterRemove)
        #expect(await index.generation == afterRemove)
    }
}

private extension GroupingCache {
    func groups(_ cached: [RankCandidate], loadPrints: PageGrouping.LoadPrints) async -> PageGroups {
        await groups(cached, key: Key(generation: 1, skipFavorites: false), loadPrints: loadPrints)
    }
}
