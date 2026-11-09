import Foundation
import SwiftData
import Testing
@testable import photo_swiper

/// Saved progress is versioned (`BristleSchemaV1`), and stores written before versioning still open
/// unchanged (JUN-22, S-4).
@MainActor
struct SchemaVersioningTests {
    private let item = LibraryItem(id: "kept-1", kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000),
                                   location: "Santa Monica", bytes: 2_500_000, image: .photoKit(localIdentifier: "kept-1"))
    private let pending = LibraryItem(id: "pile-1", kind: .photo, date: Date(timeIntervalSince1970: 1_800_000_000),
                                      location: nil, bytes: 4_000_000, image: .photoKit(localIdentifier: "pile-1"))
    private let decidedAt = Date(timeIntervalSince1970: 1_800_000_100)

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "default.store")
    }

    /// Writes progress the way builds before versioning did: a container of the bare models.
    private func writeUnversionedStore(at url: URL) throws -> SavedSession {
        let legacy = try ModelContainer(
            for: Schema([ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self]),
            configurations: ModelConfiguration(url: url)
        )
        let store = SwiftDataProgressStore(container: legacy, defaults: nil)
        store.save([
            item.id: StoredDecision(decision: .keep, decidedAt: decidedAt, sessionNumber: 3, item: item),
            pending.id: StoredDecision(decision: .delete, decidedAt: decidedAt, sessionNumber: 3, item: pending),
        ])
        let saved = SavedSession(session: Session(number: 3, cards: [.photo(item), .photo(pending)]), index: 2, marks: [:], finished: false, drafts: [:])
        store.saveSession(saved)
        return saved
    }

    @Test func aStoreFromBeforeVersioningOpensWithEverythingInIt() throws {
        let url = try temporaryStoreURL()
        let saved = try writeUnversionedStore(at: url)

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

    @Test func theContainerUsesTheVersionedSchema() throws {
        let container = try SwiftDataProgressStore.makeContainer(inMemory: true)
        #expect(container.schema.version == BristleSchemaV1.versionIdentifier)
        #expect(Set(container.schema.entities.map(\.name)) == ["ItemProgress", "SessionProgress", "AssetFeatureRecord"])
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
