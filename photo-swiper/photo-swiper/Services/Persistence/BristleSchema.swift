import Foundation
import SwiftData

/// The on-disk schema, versioned so a model change can migrate saved progress instead of failing to
/// open it.
///
/// V1 is exactly the models that shipped before versioning existed, so stores written by earlier
/// builds open as V1 with no migration and no data change. V2 adds the cleanup history
/// (`CleanupEvent`) and the category of each decision (`ItemProgress.categoryRaw`, optional). V3 adds
/// pending video trims (`ItemProgress.trimData`, optional).
///
/// Changing a model:
/// - Adding an **optional** property (or one with a default) is a lightweight change, but it still needs
///   a new version, so the history stays exact.
/// - Anything else (a rename, a type change, a new non-optional property, dropping a model) needs a
///   new version **and** a migration stage. Otherwise the store fails to open and the app falls back
///   to a throwaway store for that launch.
///
/// To add a version:
/// 1. Freeze the models that change: copy today's class into the newest `BristleSchemaVN` as a nested
///    type, exactly as it is, and point that version's `models` at the copy. A model that doesn't change
///    stays shared: both versions list the same top-level class (`SessionProgress` and
///    `AssetFeatureRecord` are shared by V1 and V2).
/// 2. Change the top-level class and add `enum BristleSchemaVN+1: VersionedSchema` listing the top-level
///    models.
/// 3. Append it to `BristleMigrationPlan.schemas` and add a stage, `.lightweight(fromVersion:toVersion:)`
///    or `.custom(…)` for data that has to be rewritten.
/// 4. Add a test that opens a store from the previous version with the new container (see
///    `SchemaVersioningTests`), with `allowsUnplannedFallback: false` so it's the plan that opens it.
/// 5. Check `SwiftDataProgressStore.makeContainer`'s fallback for stores from before versioning. It runs
///    only for stores from before V2 (`isOlderThanV2`), so it can't skip a new version's custom stage; keep
///    it that way.
enum BristleSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self]
    }

    /// `ItemProgress` as V1 shipped it, frozen. Only migration reads it.
    @Model
    final class ItemProgress {
        @Attribute(.unique) var itemID: String
        var decisionRaw: String
        var decidedAt: Date
        var sessionNumber: Int
        var bytes: Int64
        var settlementRaw: String?
        var settledAt: Date?
        var itemData: Data

        init(itemID: String, decisionRaw: String, decidedAt: Date, sessionNumber: Int, bytes: Int64, itemData: Data) {
            self.itemID = itemID
            self.decisionRaw = decisionRaw
            self.decidedAt = decidedAt
            self.sessionNumber = sessionNumber
            self.bytes = bytes
            self.itemData = itemData
        }
    }
}

/// V1 plus `CleanupEvent` and `ItemProgress.categoryRaw`.
enum BristleSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [BristleSchemaV2.ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self, CleanupEvent.self]
    }

    /// `ItemProgress` as V2 shipped it, frozen. Only migration reads it.
    @Model
    final class ItemProgress {
        @Attribute(.unique) var itemID: String
        var decisionRaw: String
        var decidedAt: Date
        var sessionNumber: Int
        var bytes: Int64
        var settlementRaw: String?
        var settledAt: Date?
        var itemData: Data
        var categoryRaw: String?

        init(itemID: String, decisionRaw: String, decidedAt: Date, sessionNumber: Int, bytes: Int64, itemData: Data) {
            self.itemID = itemID
            self.decisionRaw = decisionRaw
            self.decidedAt = decidedAt
            self.sessionNumber = sessionNumber
            self.bytes = bytes
            self.itemData = itemData
        }
    }
}

/// The current models: V2 plus `ItemProgress.trimData`.
enum BristleSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self, CleanupEvent.self]
    }
}

/// How saved progress moves between schema versions.
enum BristleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BristleSchemaV1.self, BristleSchemaV2.self, BristleSchemaV3.self] }
    /// V2 only adds a model and an optional property, and V3 only an optional property, so SwiftData moves
    /// the data over as it is. The cleanup history for deletes made before V2 is filled in by
    /// `SwiftDataProgressStore`, not here.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: BristleSchemaV1.self, toVersion: BristleSchemaV2.self),
            .lightweight(fromVersion: BristleSchemaV2.self, toVersion: BristleSchemaV3.self),
        ]
    }
}
