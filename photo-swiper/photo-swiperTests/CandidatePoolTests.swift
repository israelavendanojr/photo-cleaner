import Foundation
import Testing
@testable import photo_swiper

struct CandidatePoolTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let edited = Date(timeIntervalSince1970: 1_700_000_000)

    /// Newest first: `i0` is the newest.
    private func library(_ count: Int, favorites: Set<String> = []) -> [CandidatePool.Entry] {
        (0..<count).map { CandidatePool.Entry(id: "i\($0)", modifiedAt: edited, isFavorite: favorites.contains("i\($0)")) }
    }

    private func record(daysOld: Double = 1, sharpness: Double? = nil, dark: Double = 0, version: Int = 1, modifiedAt: Date? = nil) -> IndexedFeatures {
        var features = AssetFeatures(createdAt: now.addingTimeInterval(-daysOld * 86_400), bytes: 2_000_000)
        if let sharpness {
            features.sharpness = sharpness
            features.exposure = ExposureStats(mean: 0.1, darkFraction: dark, brightFraction: 0)
            features.aesthetic = 0
            features.isUtility = false
        }
        return IndexedFeatures(features: features, stamp: IndexStamp(modifiedAt: modifiedAt ?? edited, version: version))
    }

    @Test func indexedItemsCompeteOnCachedFeaturesAndTheRestAreReadLive() {
        let pool = CandidatePool.build(library: library(5), excluding: [], indexed: ["i1": record(), "i3": record()], poolSize: 10)
        #expect(pool.cached.map(\.id) == ["i1", "i3"])
        #expect(pool.live == ["i0", "i2", "i4"])
        #expect(pool.indexedCount == 2)
        #expect(pool.totalCount == 5)
        #expect(pool.scanPercent == 40)
    }

    @Test func poolSizeCapsOnlyTheUnindexedPart() {
        let indexed = Dictionary(uniqueKeysWithValues: (5..<10).map { ("i\($0)", record()) })
        let pool = CandidatePool.build(library: library(10), excluding: [], indexed: indexed, poolSize: 2)
        #expect(pool.live == ["i0", "i1"])
        #expect(pool.cached.count == 5, "Old indexed items still compete")
    }

    @Test func excludedItemsNeverCompeteButStillCountAsIndexed() {
        let pool = CandidatePool.build(library: library(3), excluding: ["i0", "i1"], indexed: ["i1": record()], poolSize: 10)
        #expect(pool.cached.isEmpty)
        #expect(pool.live == ["i2"])
        #expect(pool.indexedCount == 1)
    }

    @Test func staleRecordsFallBackToLiveMetadata() {
        let indexed = [
            "i0": record(version: 0),
            "i1": record(modifiedAt: edited.addingTimeInterval(-60)),
            "i2": record(),
        ]
        let pool = CandidatePool.build(library: library(3), excluding: [], indexed: indexed, poolSize: 10, version: 1)
        #expect(pool.cached.map(\.id) == ["i2"])
        #expect(pool.live == ["i0", "i1"])
    }

    @Test func favoritesComeFromTheLibraryNotTheCache() {
        var cachedFavorite = record()
        cachedFavorite.features.isFavorite = true
        let pool = CandidatePool.build(library: library(2, favorites: ["i1"]), excluding: [],
                                       indexed: ["i0": cachedFavorite, "i1": record()], poolSize: 10)
        #expect(pool.cached.first { $0.id == "i0" }?.features.isFavorite == false)
        #expect(pool.cached.first { $0.id == "i1" }?.features.isFavorite == true)
    }

    @Test func aCompleteIndexHasNoScanPercent() {
        let pool = CandidatePool.build(library: library(2), excluding: [], indexed: ["i0": record(), "i1": record()], poolSize: 10)
        #expect(pool.scanPercent == nil)
        #expect(CandidatePool.build(library: [], excluding: [], indexed: [:], poolSize: 10).scanPercent == nil)
    }

    @Test func anOldIndexedAccidentalOutranksANewLivePhotoInOnePool() {
        // i0 is new and unindexed; i9 is a year old, indexed, and mostly black with no detail.
        let pool = CandidatePool.build(library: library(10), excluding: [],
                                       indexed: ["i9": record(daysOld: 365, sharpness: 1, dark: 1)], poolSize: 3)
        let live = pool.live.map { RankCandidate(id: $0, features: AssetFeatures(createdAt: now.addingTimeInterval(-3600), bytes: 2_000_000)) }
        let plan = SessionPlanner(limit: 2, minBatch: 3, maxBatch: 40).plan(pool.cached + live, now: now)
        #expect(plan.first == .single("i9"))
        #expect(plan.count == 2)
    }
}
