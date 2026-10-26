import CoreData
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

        let session = MockFeedBuilder().makeSessionNow(number: 3)
        let item = session.items[0]
        let decision = StoredDecision(decision: .delete, decidedAt: date, sessionNumber: 3, item: item)
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

    @Test func featurePrintsAndBurstsRoundTripApartFromTheFeatures() async throws {
        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(inMemory: true))
        let print = FeaturePrint(vector: [0.25, -0.5, 1])
        var features = entry("a").features
        features.burstID = "burst-1"
        features.isUserBurstPick = true
        let printed = IndexEntry(id: "a", features: features, modifiedAt: date, version: 2, indexedAt: date, featurePrint: print.data)
        await index.upsert([printed, entry("b")])

        #expect(await index.indexed()["a"]?.features == features)
        #expect(await index.featurePrints(for: ["a", "b", "missing"]) == ["a": print])

        // Re-indexing without a print (Vision failed) clears the old one.
        await index.upsert([IndexEntry(id: "a", features: features, modifiedAt: date, version: 2, indexedAt: date)])
        #expect(await index.featurePrints(for: ["a"]).isEmpty)
    }

    /// A store written by the first index version opens with the new fields empty. Its records still
    /// rank in the feed, but the indexer redoes them to add feature prints.
    @Test func recordsFromTheFirstIndexVersionMigrateAndAreRedone() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("progress.store")
        try IndexSchemaV1.writeStore(at: url, id: "a", createdAt: date, modifiedAt: date)

        let index = FeatureIndex(container: try SwiftDataProgressStore.makeContainer(url: url))
        let record = try #require(await index.indexed()["a"])
        #expect(record.stamp == IndexStamp(modifiedAt: date, version: 1))
        #expect(record.features.sharpness == 120)
        #expect(record.features.burstID == nil)
        #expect(record.features.isUserBurstPick == nil)
        #expect(await index.featurePrints(for: ["a"]).isEmpty)

        #expect(!IndexFreshness.isCurrent(record.stamp, assetModifiedAt: date), "The indexer redoes it")
        let pool = CandidatePool.build(library: [CandidatePool.Entry(id: "a", modifiedAt: date, isFavorite: false)],
                                       excluding: [], indexed: ["a": record], poolSize: 10)
        #expect(pool.cached.map(\.id) == ["a"], "The feed still ranks on it meanwhile")

        let print = FeaturePrint(vector: [1, 0])
        await index.upsert([IndexEntry(id: "a", features: record.features, modifiedAt: date, version: 2, indexedAt: date, featurePrint: print.data)])
        #expect(await index.featurePrints(for: ["a"]) == ["a": print])
    }
}

/// The feature index as its first version stored it, to test migrating from it.
///
/// Built as a Core Data model rather than a second `@Model` class: SwiftData resolves models by
/// entity name process-wide, so a test class named `AssetFeatureRecord` would shadow the app's
/// for every test running alongside. SwiftData stores are Core Data stores, and the store keeps
/// its model, so opening it with the app's schema runs the same lightweight migration a device does.
private enum IndexSchemaV1 {
    static func writeStore(at url: URL, id: String, createdAt: Date, modifiedAt: Date) throws {
        let container = NSPersistentContainer(name: "IndexV1", managedObjectModel: model())
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let context = container.viewContext
        let record = NSEntityDescription.insertNewObject(forEntityName: "AssetFeatureRecord", into: context)
        let values: [String: Any] = [
            "localIdentifier": id, "createdAt": createdAt, "bytes": Int64(3_000_000), "isVideo": false,
            "duration": 0.0, "isScreenshot": false, "isFavorite": false, "isInBurst": true, "isBurstPick": false,
            "hasAdjustments": false, "sharpness": 120.0, "modifiedAt": modifiedAt, "featureVersion": 1,
            "indexedAt": createdAt,
        ]
        record.setValuesForKeys(values)
        try context.save()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Mirrors `AssetFeatureRecord` at index version 1.
    private static func model() -> NSManagedObjectModel {
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }
        let entity = NSEntityDescription()
        entity.name = "AssetFeatureRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("localIdentifier", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("bytes", .integer64AttributeType),
            attribute("isVideo", .booleanAttributeType),
            attribute("duration", .doubleAttributeType),
            attribute("isScreenshot", .booleanAttributeType),
            attribute("isFavorite", .booleanAttributeType),
            attribute("isInBurst", .booleanAttributeType),
            attribute("isBurstPick", .booleanAttributeType),
            attribute("hasAdjustments", .booleanAttributeType),
            attribute("sharpness", .doubleAttributeType, optional: true),
            attribute("exposureMean", .doubleAttributeType, optional: true),
            attribute("darkFraction", .doubleAttributeType, optional: true),
            attribute("brightFraction", .doubleAttributeType, optional: true),
            attribute("aesthetic", .doubleAttributeType, optional: true),
            attribute("isUtility", .booleanAttributeType, optional: true),
            attribute("modifiedAt", .dateAttributeType, optional: true),
            attribute("featureVersion", .integer64AttributeType),
            attribute("indexedAt", .dateAttributeType),
        ]
        entity.uniquenessConstraints = [["localIdentifier"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
