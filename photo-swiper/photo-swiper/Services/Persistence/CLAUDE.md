# Persistence — local rules

Saved progress lives here. A mistake loses the user's decisions or stops the app from launching. Changes need human review.

- **Write-through.** Every mutating `ProgressStoring` call is durable when it returns: save inside the call, never batch or defer. `ProgressWritesTests` guards it.
- **Model changes go through `BristleSchema.swift`.** Follow the "To add V2" steps in its doc comment. Freeze V1 as nested types first, then add V2, a migration stage, and a test that opens a V1 store (`SchemaVersioningTests`).
- **A version that only adds `#Index` aborts at launch.** Indexes don't change the version checksum, so SwiftData rejects the plan ("Duplicate version checksums detected"). Pair an index with a real model change, or leave it out.
- **Old JSON must still decode.** `ItemProgress` stores `LibraryItem` (with `AssetFeatures`) and `SessionProgress` stores `Session` as JSON. Synthesized `Codable` ignores property defaults, so a new field must be optional, or every saved pile item fails to decode.
- `AssetFeatureRecord` (in `Services/Index/`) is in the same schema, so the same rules apply to it.
- Keep `InMemoryProgressStore` (`Services/Mock/`) behaving the same: tests run against both stores (`ProgressStoreTests.Kind`).
- Run `make test-unit` after any change here; the persistence suites run against SwiftData in memory.
