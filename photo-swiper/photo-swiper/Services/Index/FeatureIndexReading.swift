import Foundation

/// Read access to cached features. `FeatureIndex` is the real one; tests use a fake.
protocol FeatureIndexReading: Sendable {
    /// Every cached record, without feature prints. Callers decide which are still fresh with `IndexFreshness`.
    func indexed() async -> [LibraryItem.ID: IndexedFeatures]
    /// Stored feature prints for `ids`. Items without one are left out.
    func featurePrints(for ids: [LibraryItem.ID]) async -> [LibraryItem.ID: FeaturePrint]
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
    /// A `FeaturePrint`'s bytes; nil when not analyzed or Vision failed.
    var featurePrint: Data? = nil
}

/// The one rule for "this record can be used as is", shared by the indexer's work queue and the feed.
enum IndexFreshness {
    /// Bump when analysis changes or adds a stored value; the indexer redoes every older record.
    /// 2 added feature prints, burst identifiers, and the user's burst pick.
    static let currentVersion = 2
    /// The oldest version the feed still ranks on. Bump only when a stored value changes meaning, so a
    /// re-analysis doesn't drop ranking back to the live pool until the whole library is redone.
    static let rankableVersion = 1

    static func isCurrent(_ stamp: IndexStamp, assetModifiedAt: Date?, version: Int = currentVersion) -> Bool {
        stamp.version >= version && stamp.modifiedAt == assetModifiedAt
    }
}
