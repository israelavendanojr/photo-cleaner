---
paths:
  - "photo-swiper/photo-swiper/Services/Persistence/**"
  - "photo-swiper/photo-swiper/Services/Index/AssetFeatureRecord.swift"
---

# Persistence — local rules

Saved progress lives here. A mistake loses the user's decisions or stops the app from launching. Changes need human review.

- **Write-through.** Every mutating `ProgressStoring` call is durable when it returns: save inside the call, never batch or defer. `ProgressWritesTests` guards it.
- **Model changes go through `BristleSchema.swift`.** Follow the "To add a version" steps in its doc comment: freeze the models that change as nested types of the newest version, add the next version and a migration stage, and add a test that opens the previous version's store through the plan (`SchemaVersioningTests`, `allowsUnplannedFallback: false`). The unplanned fallback in `makeContainer` is only for stores from before V2.
- **A version that only adds `#Index` aborts at launch.** Indexes don't change the version checksum, so SwiftData rejects the plan ("Duplicate version checksums detected"). Pair an index with a real model change, or leave it out.
- **Old JSON must still decode.** `ItemProgress` stores `LibraryItem` (with `AssetFeatures`) and `SessionProgress` stores `Session` as JSON. Synthesized `Codable` ignores property defaults, so a new field must be optional, or every saved pile item fails to decode.
- `AssetFeatureRecord` (in `Services/Index/`) is in the same schema, so the same rules apply to it.
- Keep `InMemoryProgressStore` (`Services/Mock/`) behaving the same: tests run against both stores (`ProgressStoreTests.Kind`).
- Run `make test-unit` after any change here; the persistence suites run against SwiftData in memory.
