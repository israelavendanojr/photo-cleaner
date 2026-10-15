import Foundation

/// Read access to cached features. `FeatureIndex` is the real one; tests use a fake.
protocol FeatureIndexReading: Sendable {
    /// Every cached record. Callers decide which are still fresh with `IndexFreshness`.
    func indexed() async -> [LibraryItem.ID: IndexedFeatures]
}

/// What decides whether a record is stale: the asset's edit date and the analysis version.
struct IndexStamp: Hashable, Sendable {
    var modifiedAt: Date?
    var version: Int
}

/// One cached record, as readers see it.
struct IndexedFeatures: Hashable, Sendable {
    var features: AssetFeatures
    var stamp: IndexStamp
}

/// One record to write.
struct IndexEntry: Sendable {
    let id: LibraryItem.ID
    let features: AssetFeatures
    let modifiedAt: Date?
    let version: Int
    let indexedAt: Date
}

/// The one rule for "this record can be used as is", shared by the indexer's work queue and the feed.
enum IndexFreshness {
    /// Bump when analysis changes in a way that shifts stored values; every record is redone.
    static let currentVersion = 1

    static func isCurrent(_ stamp: IndexStamp, assetModifiedAt: Date?, version: Int = currentVersion) -> Bool {
        stamp.version >= version && stamp.modifiedAt == assetModifiedAt
    }
}
