import Foundation
import SwiftData
import Testing
@testable import photo_swiper

struct FeatureIndexStoreTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ id: String, sharpness: Double? = 120, modifiedAt: Date? = nil, version: Int = 1) -> IndexEntry {
        IndexEntry(
            id: id,
            features: AssetFeatures(
                createdAt: date, bytes: 3_000_000, isInBurst: true, hasAdjustments: true, sharpness: sharpness,
                exposure: sharpness == nil ? nil : ExposureStats(mean: 0.4, darkFraction: 0.1, brightFraction: 0.02),
                aesthetic: sharpness == nil ? nil : -0.25, isUtility: sharpness == nil ? nil : true
            ),
            modifiedAt: modifiedAt ?? date, version: version, indexedAt: date
        )
    }

    @Test func aRecordRoundTrips() async throws {
        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
        let analyzed = entry("a"), metadataOnly = entry("b", sharpness: nil)
        await index.upsert([analyzed, metadataOnly])

        let all = await index.indexed()
        #expect(all["a"] == IndexedFeatures(features: analyzed.features, stamp: IndexStamp(modifiedAt: date, version: 1)))
        #expect(all["b"]?.features == metadataOnly.features)
        #expect(await index.stamps() == ["a": IndexStamp(modifiedAt: date, version: 1), "b": IndexStamp(modifiedAt: date, version: 1)])
    }

    @Test func upsertReplacesAndRemoveDeletes() async throws {
        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
        await index.upsert([entry("a"), entry("b")])
        await index.upsert([entry("a", sharpness: 5, version: 2)])
        #expect(await index.count() == 2)
        #expect(await index.indexed()["a"]?.features.sharpness == 5)
        #expect(await index.stamps()["a"]?.version == 2)

        await index.remove(["a", "missing"])
        #expect(await index.stamps().keys.sorted() == ["b"])
    }

    @Test func freshnessNeedsTheCurrentVersionAndAnUnchangedEditDate() {
        let stamp = IndexStamp(modifiedAt: date, version: 1)
        #expect(IndexFreshness.isCurrent(stamp, assetModifiedAt: date, version: 1))
        #expect(!IndexFreshness.isCurrent(stamp, assetModifiedAt: date, version: 2))
        #expect(!IndexFreshness.isCurrent(stamp, assetModifiedAt: date.addingTimeInterval(1), version: 1))
        #expect(!IndexFreshness.isCurrent(stamp, assetModifiedAt: nil, version: 1))
    }

    /// A store written before the index existed opens with the new schema and keeps its progress.
    @MainActor
    @Test func savedProgressFromBeforeTheIndexStillLoads() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("progress.store")

        let session = MockFeedBuilder().makeSessionNow(number: 4)
        let item = session.items[0]
        let decision = StoredDecision(decision: .delete, decidedAt: date, sessionNumber: 4, item: item)
        let saved = SavedSession(session: session, index: 2, marks: [:], finished: false)
        do {
            let oldSchema = Schema([ItemProgress.self, SessionProgress.self])
            let old = try ModelContainer(for: oldSchema, configurations: ModelConfiguration(schema: oldSchema, url: url))
            let store = SwiftDataProgressStore(container: old, defaults: nil)
            store.save([item.id: decision])
            store.saveSession(saved)
        }

        let container = try SwiftDataProgressStore.makeContainer(url: url)
        let reopened = SwiftDataProgressStore(container: container, defaults: nil)
        #expect(reopened.decisions(for: [item.id])[item.id] == decision)
        #expect(reopened.loadSession() == saved)
        #expect(reopened.pile().map(\.id) == [item.id])

        // The new model works in the migrated store too.
        let index = FeatureIndex(container: container)
        await index.upsert([entry(item.id)])
        #expect(await index.count() == 1)
    }
}
