import SwiftData

/// The on-disk schema, versioned so a future model change can migrate saved progress instead of
/// failing to open it.
///
/// V1 is exactly the models that shipped before versioning existed, so stores written by earlier
/// builds open as V1 with no migration and no data change.
///
/// Changing a model:
/// - Adding an **optional** property (or one with a default) is a lightweight change SwiftData
///   handles on its own. It still belongs in a new version once V2 exists, so the history stays exact.
/// - Anything else (a rename, a type change, a new non-optional property, dropping a model) needs a
///   new version **and** a migration stage. Otherwise the store fails to open and the app falls back
///   to a throwaway store for that launch.
///
/// To add V2:
/// 1. Freeze V1: move today's model classes into `BristleSchemaV1` as nested types
///    (`BristleSchemaV1.ItemProgress`, …) and point `models` at them.
/// 2. Add `enum BristleSchemaV2: VersionedSchema` with `Schema.Version(2, 0, 0)` and the new models,
///    and make the app's top-level names typealiases to the V2 types.
/// 3. Append V2 to `BristleMigrationPlan.schemas` and add a stage, `.lightweight(fromVersion:toVersion:)`
///    or `.custom(…)` for data that has to be rewritten.
/// 4. Add a test that opens a V1 store with the new container (see `SchemaVersioningTests`).
enum BristleSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self]
    }
}

/// How saved progress moves between schema versions. One version so far, so nothing to migrate.
enum BristleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BristleSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
