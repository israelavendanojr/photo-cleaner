import CoreData
import Foundation
import SwiftData
import Testing
@testable import photo_swiper

/// Saved progress is versioned (`BristleSchema.swift`). Stores written before versioning, and V1 stores,
/// still open with everything in them (JUN-22, S-4; V2 in JUN-9).
@MainActor
struct SchemaVersioningTests {
    private let item = LibraryItem(id: "kept-1", kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000),
                                   location: "Santa Monica", bytes: 2_500_000, image: .photoKit(localIdentifier: "kept-1"))
    private let pending = LibraryItem(id: "pile-1", kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000),
                                      location: nil, bytes: 4_000_000, image: .photoKit(localIdentifier: "pile-1"))
    private let deleted = LibraryItem(id: "gone-1", kind: .video(duration: 12), date: Date(timeIntervalSince1970: 1_800_000_000),
                                      location: nil, bytes: 90_000_000, image: .photoKit(localIdentifier: "gone-1"))
    private let decidedAt = Date(timeIntervalSince1970: 1_800_000_100)
    private let settledAt = Date(timeIntervalSince1970: 1_800_000_200)

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "default.store")
    }

    /// Writes progress as V1 builds did, through the frozen V1 models: a deleted item, a kept one, a
    /// pending one, and the deck. `versioned` false writes it as builds before versioning did, a
    /// container of the bare models.
    @discardableResult
    private func writeV1Store(at url: URL, versioned: Bool) throws -> SavedSession {
        let schema = versioned
            ? Schema(versionedSchema: BristleSchemaV1.self)
            : Schema([BristleSchemaV1.ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let encoder = JSONEncoder()
        for (item, decision, settled) in [(item, Decision.keep, false), (pending, .delete, false), (deleted, .delete, true)] {
            let row = BristleSchemaV1.ItemProgress(itemID: item.id, decisionRaw: decision.rawValue, decidedAt: decidedAt,
                                                   sessionNumber: 3, bytes: item.bytes, itemData: try encoder.encode(item))
            if settled {
                row.settlementRaw = Settlement.deleted.rawValue
                row.settledAt = settledAt
            }
            context.insert(row)
        }
        let saved = SavedSession(session: Session(number: 3, cards: [.photo(item), .photo(pending)]), index: 2, marks: [:], finished: false, drafts: [:])
        let row = SessionProgress(number: 3, index: 2, finished: false, startedAt: decidedAt,
                                  snapshot: try encoder.encode(saved.session), marks: try encoder.encode(saved.marks))
        row.drafts = try encoder.encode(saved.drafts)
        context.insert(row)
        try context.save()
        return saved
    }

    @Test func aStoreFromBeforeVersioningOpensWithEverythingInIt() throws {
        let url = try temporaryStoreURL()
        let saved = try writeV1Store(at: url, versioned: false)

        let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)

        let decisions = store.decisions(for: [item.id, pending.id])
        #expect(decisions[item.id]?.decision == .keep)
        #expect(decisions[item.id]?.item == item)
        #expect(decisions[pending.id]?.decision == .delete)
        #expect(store.pile() == [pending])
        #expect(store.loadSession()?.session == saved.session)
        #expect(store.loadSession()?.index == 2)
        #expect(store.lastSessionNumber() == 3)
    }

    @Test func aV1StoreOpensAsV2WithEverythingInIt() throws {
        let url = try temporaryStoreURL()
        let saved = try writeV1Store(at: url, versioned: true)

        let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)

        let decisions = store.decisions(for: [item.id, pending.id, deleted.id])
        #expect(decisions[item.id]?.decision == .keep)
        #expect(decisions[item.id]?.category == nil, "V1 rows have no category")
        #expect(store.pile() == [pending])
        #expect(store.freedBytes() == deleted.bytes)
        #expect(store.loadSession()?.session == saved.session)
    }

    @Test func deletesFromBeforeTheHistoryAreFilledInOnce() throws {
        let url = try temporaryStoreURL()
        try writeV1Store(at: url, versioned: true)
        let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)

        let history = store.cleanupHistory()
        #expect(history == [CleanupEntry(at: Calendar.current.startOfDay(for: settledAt), category: .video, count: 1, bytes: deleted.bytes)])

        // A new delete adds to the history without filling it in again, here or after a relaunch.
        let later = CleanupEntry(at: settledAt.addingTimeInterval(86_400), category: .photo, count: 2, bytes: 5_000_000)
        store.recordCleanup([later])
        let reopened = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)
        #expect(reopened.cleanupHistory() == history + [later])
    }

    @Test func theVersionedStoreRoundTrips() throws {
        let url = try temporaryStoreURL()
        do {
            let store = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)
            store.save([pending.id: StoredDecision(decision: .delete, decidedAt: decidedAt, sessionNumber: 1, item: pending)])
            store.settle([pending.id], as: .deleted)
        }

        let reopened = SwiftDataProgressStore(container: try SwiftDataProgressStore.makeContainer(url: url), defaults: nil)
        #expect(reopened.decisions(for: [pending.id])[pending.id]?.settlement == .deleted)
        #expect(reopened.freedBytes() == pending.bytes)
    }

    @Test(arguments: [false, true])
    func v1StoresOpenThroughTheMigrationPlan(versioned: Bool) throws {
        let url = try temporaryStoreURL()
        try writeV1Store(at: url, versioned: versioned)

        let store = SwiftDataProgressStore(
            container: try SwiftDataProgressStore.makeContainer(url: url, allowsUnplannedFallback: false), defaults: nil
        )
        #expect(store.pile() == [pending])
    }

    @Test func aStoreFromBeforeTheIndexIsMigratedOnceThenOpensThroughThePlan() throws {
        let url = try temporaryStoreURL()
        do {
            let schema = Schema([BristleSchemaV1.ItemProgress.self, SessionProgress.self])
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(old)
            context.insert(BristleSchemaV1.ItemProgress(itemID: pending.id, decisionRaw: Decision.delete.rawValue, decidedAt: decidedAt,
                                                        sessionNumber: 1, bytes: pending.bytes, itemData: try JSONEncoder().encode(pending)))
            try context.save()
        }
        #expect(SwiftDataProgressStore.isOlderThanV2(storeAt: url, schema: Schema(versionedSchema: BristleSchemaV2.self)))
        #expect(throws: (any Error).self) {
            try SwiftDataProgressStore.makeContainer(url: url, allowsUnplannedFallback: false)
        }

        _ = try SwiftDataProgressStore.makeContainer(url: url)

        let reopened = SwiftDataProgressStore(
            container: try SwiftDataProgressStore.makeContainer(url: url, allowsUnplannedFallback: false), defaults: nil
        )
        #expect(reopened.pile() == [pending], "Migrated once; the next launch opens it through the plan")
    }

    /// A store from a later version (here: the cleanup history with a field this build doesn't know) is
    /// refused and left as it is, never migrated down.
    @Test func aStoreFromANewerBuildIsRefusedNotMigratedDown() throws {
        let url = try temporaryStoreURL()
        let model = NSManagedObjectModel()
        let event = NSEntityDescription()
        event.name = "CleanupEvent"
        let future = NSAttributeDescription()
        future.name = "addedInV3"
        future.attributeType = .stringAttributeType
        future.isOptional = true
        event.properties = [future]
        model.entities = [event]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let written = try coordinator.addPersistentStore(type: .sqlite, at: url)
        try coordinator.remove(written)

        #expect(!SwiftDataProgressStore.isOlderThanV2(storeAt: url, schema: Schema(versionedSchema: BristleSchemaV2.self)))
        #expect(throws: (any Error).self) { try SwiftDataProgressStore.makeContainer(url: url) }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let entities = (metadata[NSStoreModelVersionHashesKey] as? [String: Any])?.keys.sorted()
        #expect(entities == ["CleanupEvent"], "The file is left as it was")
    }

    @Test func theContainerUsesTheVersionedSchema() throws {
        let container = try SwiftDataProgressStore.makeContainer(inMemory: true)
        #expect(container.schema.version == BristleSchemaV2.versionIdentifier)
        #expect(Set(container.schema.entities.map(\.name)) == ["ItemProgress", "SessionProgress", "AssetFeatureRecord", "CleanupEvent"])
    }

    @Test func aStoreThatWouldNotOpenIsSaidOnce() {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(),
                               defaults: freshDefaults(), progressLoadFailed: true)
        #expect(vm.isProgressLoadNoticePresented)

        vm.dismissProgressLoadNotice()
        #expect(!vm.isProgressLoadNoticePresented)
    }

    @Test func noNoticeWhenProgressOpened() {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(), defaults: freshDefaults())
        #expect(!vm.isProgressLoadNoticePresented)
    }
}
