# Architecture — Bristle

> Draft from the JUN-5 audit (2026-11-08). Check it against the code before moving it to the repo root.
> Update this file in the same PR as any change to module boundaries or data flow.

Bristle is an iOS 18+ SwiftUI app that helps people clear their photo library by swiping. Everything runs on the device. Photos are deleted only after the user confirms twice, and they go to Recently Deleted.

## Names

The app has had several names. They differ on purpose, and the permanent ones can't change after release.

| Thing | Name | Can change? |
|---|---|---|
| Repo | `photo-cleaner` | Yes, but links and worktrees use it |
| Xcode project / scheme | `photo-swiper/photo-swiper.xcodeproj` / `photo-swiper` | The scheme could become `Bristle`; nothing else depends on it but commands and CI |
| App target / Swift module (for `@testable import`) | `photo-swiper` / `photo_swiper` | No: tests, previews and every command name it |
| Test targets | `photo-swiperTests` (Swift Testing), `photo-swiperUITests` (XCTest) | No |
| Bundle ID | `com.israelavendanojr.photo-swiper` | **Never.** It's the App Store identity and the on-device data |
| Unlock product ID | `com.israelavendanojr.photo-swiper.unlock` (`StoreKitEntitlementStore.unlock`) | **Never.** Purchases are tied to it |
| Log subsystem | `com.israelavendanojr.photo-swiper` (`Logger.appSubsystem`) | Yes, but log-stream commands use it |
| Display name | `Bristle`. Set it only in `AppName.xcconfig` | Yes, in that one place |

## Layers

```
Views (SwiftUI)  ──reads/intents──▶  FeedViewModel (@MainActor, @Observable façade)
                                       ├─ SwipeGate          allowance, paywall, free pile cap
                                       ├─ OnboardingFlow     first-launch steps
                                       ├─ ReminderController refill reminders, clutter estimate
                                       └─ FollowUpCoordinator review prompt / post-delete upsell
FeedViewModel ──protocols──▶ Services
   PhotoLibraryProviding  → PhotoKitLibrary        access, delete, change observer
   FeedBuilding           → PhotoKitFeedBuilder    (actor) builds ~20-item pages
   ProgressStoring        → SwiftDataProgressStore (main context) decisions + saved deck
   EntitlementStore       → StoreKitEntitlementStore (wrapped by DebugOverrideEntitlementStore)
   IndexScheduler → LibraryIndexer → IndexAssetSource (PhotoKitIndexSource) + ImageAnalyzing (VisionImageAnalyzer)
                                   → FeatureIndex (actor, own ModelContext)
Pure core (no PhotoKit, no UI; unit-tested):
   Ranking/  CandidatePool, DuplicateGrouper, DuplicatePick, SimilarGrouper, BestPick, FeedRanker, SessionPlanner, FrontLoad
   Analysis/ Sharpness, Exposure, DHash, FeaturePrint, ImageFlags
Shared helpers: ThumbnailPipeline.shared (PHCachingImageManager), PlaceNamer (CLGeocoder), DevMode.shared, FreeTierTunables.shared
```

**Rules the structure relies on**

- Views never touch PhotoKit or SwiftData. Pixels go through `ItemImage` / `ThumbnailPipeline`, and video through `VideoSource`.
- Collaborators never call each other. Effects that span them are sequenced in `FeedViewModel`.
- Anything that touches the system sits behind a protocol with a mock in `Services/Mock/` (`#if DEBUG`).
- Ranking and grouping stay pure and deterministic (ties broken by ID), so they can be tested with made-up features and vectors.

## Data flow

1. **Launch.** `photo_swiperApp.launch()` builds the real services, or mocks in Debug with `-mockLibrary YES` / `-startAt …`. Progress and the index share one SwiftData container (`default.store`).
2. **Access.** `vm.start()` shows onboarding before the first system prompt, then calls `requestAccess()` for `.readWrite`, which comes back as `full`, `limited` or `denied`.
3. **Index (background, foreground-only).** `LibraryIndexer.run()` diffs the library against `AssetFeatureRecord`s. For each new or edited photo it takes a local 512 px image (never downloads) and computes sharpness, exposure, a dHash, Vision's aesthetics score and utility flag, and a feature print. It saves in batches of 50 and can resume.
4. **Pages.** When 5 or fewer cards are left, `PhotoKitFeedBuilder.makeSession` runs the steps below and returns `Session.cards`:
   - `CandidatePool` takes indexed undecided items plus the newest 500 unindexed ones;
   - `DuplicateGrouper` and `DuplicatePick` find copies;
   - `SimilarGrouper` and `BestPick` find near-identical shots;
   - `FeedRanker` and `SessionPlanner` pick the top 20, batching screenshots by week;
   - `PlaceNamer` adds captions.
5. **Decide.** A swipe calls `vm.decide`, which computes per-item `Decision`s (keep / delete / later). The decisions are written through to `ItemProgress` and the deck to `SessionProgress` right away. **Nothing touches the library.**
6. **Delete.** Delete decisions form the **pile**. The only delete path is `PendingPileView`: an in-app alert, then `vm.deleteNow`, then `PhotoKitLibrary.delete` (`PHAssetChangeRequest.deleteAssets`), which shows iOS's own confirmation. The result is settled per item as `deleted`, `gone` or `undeletable`.
7. **External changes.** `PHPhotoLibraryChangeObserver` reports removed IDs. Those items are settled as `gone`, pruned from upcoming cards, and removed from the index.

## Persistence

| Store | What | Notes |
|---|---|---|
| `ItemProgress` | One row per decided asset: decision, settlement, page number, `LibraryItem` JSON | Unique by `itemID` (`PHAsset.localIdentifier`). `SwiftDataProgressStore` mirrors each row's decision, date and settlement in memory once the first page is built, for the reviewed count and page exclusions |
| `SessionProgress` | The current deck as JSON, plus index, marks and drafts | One row. A swipe that doesn't change the cards rewrites only index, marks and drafts (`DeckWrite.position`) |
| `AssetFeatureRecord` | Cached features and feature print (external storage) | Can be rebuilt from the library |
| UserDefaults | Allowance, onboarding, reminder log, dev tunables, cached unlock | Keys in `DefaultsKey` |

The models are versioned (`BristleSchemaV1`, `BristleMigrationPlan`); `BristleSchema.swift` has the steps for adding V2. A version that only adds `#Index` doesn't work: indexes don't change Core Data's version checksum, so SwiftData rejects the plan ("Duplicate version checksums detected") and the app aborts at launch (found in JUN-45). Saved JSON (`LibraryItem`, `Session`) must still decode older data.

`PhotoKitFeedBuilder` keeps the index's records and its grouping work between pages until `FeatureIndex.generation` changes (`GroupingCache`). Feature prints are never kept in memory.

## Build variants

- **Debug.** Launch arguments are documented in `photo_swiperApp.swift`. Mocks and `MockAssets.xcassets` are available. Developer mode is on.
- **Release.** Mocks are compiled out. Developer mode exists only for TestFlight and Xcode installs (`AppTransaction`), never for App Store builds.

## Decisions worth knowing (lightweight ADRs)

- **On-device only.** No accounts, analytics or crash SDKs. The only network calls go to Apple: iCloud downloads, StoreKit, and the `CLGeocoder` place names. That last one needs disclosure; see the audit, S-2.
- **Write-through persistence.** Every decision is durable when `decide` returns, so force-quitting never loses work.
- **Pile, then confirm, then system prompt.** A swipe never deletes. That's the main safety property; keep it.
- **Endless deck.** Pages are appended. Cards more than 30 behind are trimmed, and their pending deletes carry on in the pile.
- **Index is resumable by diff, not cursor.** A cancelled run loses nothing.
