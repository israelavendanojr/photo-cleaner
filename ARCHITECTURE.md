# Architecture — Bristle

> Update this file in the same PR as any change to module boundaries, data flow or a safety property.
> It names symbols, not line numbers. How a function works belongs in its doc comment, not here.

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
                                       ├─ SwipeGate           allowance, paywall, free pile cap
                                       ├─ OnboardingFlow      first-launch steps
                                       ├─ ReminderController  refill reminders, clutter estimate
                                       ├─ FollowUpCoordinator review prompt / post-delete upsell
                                       ├─ DashboardController the Library tab's numbers, computed off the main actor, cached in Caches
                                       └─ AdminController     the Admin tab's tools (Developer mode), as `vm.admin`
                                     FeedTypes.swift: the view model's small value types (FeedPhase, PaywallStatus, …)
FeedViewModel ──protocols──▶ Services
   PhotoLibraryProviding  → PhotoKitLibrary        access, delete, change observer
   FeedBuilding           → PhotoKitFeedBuilder    (actor) builds ~20-item pages; `libraryScan` for the dashboard
                               ├─ AssetCatalog → PhotoKitAssetCatalog   library reads
                               ├─ Geocoding    → CLGeocoding, via PlaceNamer   place names
                               └─ GroupingCache  grouping work, kept until FeatureIndex.generation changes
   ProgressStoring        → SwiftDataProgressStore (main context) decisions + saved deck + cleanup history
   EntitlementStore       → StoreKitEntitlementStore (wrapped by DebugOverrideEntitlementStore)
   IndexScheduler → LibraryIndexer → IndexAssetSource (PhotoKitIndexSource) + ImageAnalyzing (VisionImageAnalyzer)
                                   → FeatureIndex (actor, own ModelContext)
Pure core (no PhotoKit, no UI; unit-tested):
   Ranking/  CandidatePool, DuplicateGrouper, DuplicatePick, SimilarGrouper, BestPick, FeedRanker, SessionPlanner, FrontLoad, FeedFocus
   Analysis/ Sharpness, Exposure, DHash, FeaturePrint, ImageFlags
   Dashboard/ LibraryScan (what's left to clear, by kind), DashboardStats (history + scan → DashboardSnapshot)
Shared helpers: ThumbnailPipeline.shared (PHCachingImageManager), DevMode.shared, FreeTierTunables.shared
```

**Rules the structure relies on**

- Views never touch PhotoKit or SwiftData. Pixels go through `ItemImage` / `ThumbnailPipeline`, and video through `VideoSource`.
- Collaborators never call each other. Effects that span them are sequenced in `FeedViewModel`. `AdminController` changes the deck only through the view model's own intents.
- Admin Tools are a tab (`AppTab.admin`, `AdminToolsView`) shown only while Developer mode is on; turning it off on that tab goes back to Feed. Settings keeps only the Developer mode switch and the version-row taps. Anything Admin Tools raise (upsell screens, the swipe wall, a test notification) comes up over the Admin tab and closes back to it; RootView presents the swipe wall over any tab.
- Anything that touches the system sits behind a protocol, with a mock in `Services/Mock/` (`#if DEBUG`) or a fake in the tests (`AssetCatalog`, `Geocoding`).
- Ranking and grouping stay pure and deterministic (ties broken by ID), so they can be tested with made-up features and vectors.

## Data flow

1. **Launch.** `photo_swiperApp` builds the real services, or mocks in Debug with `-mockLibrary YES` / `-startAt …` (every launch argument is listed in the doc comment on `launch()`). Progress and the index share one SwiftData container.
2. **Access.** `vm.start()` shows onboarding before the first system prompt, then calls `requestAccess()` for `.readWrite`, which comes back as `LibraryAccess.full`, `.limited` or `.denied`. `currentAccess()` reads it again without prompting. Under limited access, `addMorePhotos()` calls `presentLimitedPicker()`.
3. **Index (background, foreground-only).** `LibraryIndexer` diffs the library against `AssetFeatureRecord`s. For each new or edited photo it takes a local 512 px image (never downloads) and computes sharpness, exposure, a dHash, Vision's aesthetics score and utility flag, and a feature print. It saves in batches and can resume. Each change bumps `FeatureIndex.generation`.
4. **Pages.** When few cards are left (`fillIfNeeded`), `PhotoKitFeedBuilder.makeSession` builds the next page from `AssetCatalog` reads:
   - `CandidatePool` takes indexed undecided items plus the newest unindexed ones;
   - `DuplicateGrouper` and `DuplicatePick` find copies; `SimilarGrouper` and `BestPick` find near-identical shots (both cached in `GroupingCache`);
   - `FeedRanker` and `SessionPlanner` pick the page, batching screenshots by week; `FrontLoad` moves strong cards forward, never the one on top;
   - with `FeedOptions.focus` set (a dashboard suggestion, `vm.focusFeed(on:)`), `FeedFocus` first narrows the candidates and groups to one `CleanupCategory`. Focusing keeps the current card and drops only the cards after it that don't fit; it isn't saved;
   - `PlaceNamer` adds captions from approximate locations (see Safety properties).
5. **Decide.** A swipe calls `vm.decide(_:cardID:)`. It applies only if `cardID` is still the current card, so a page that lands mid-swipe can't redirect it. Per-item `Decision`s (keep / delete / later) are written through to `ItemProgress`, and the deck to `SessionProgress`, before `decide` returns. **Nothing touches the library.**
6. **Delete.** Delete decisions form the **pile**. The only delete path is `PendingPileView`: its in-app alert, then `vm.deleteNow`, then `PhotoKitLibrary.delete` (`PHAssetChangeRequest.deleteAssets`), which shows iOS's own confirmation. `DeletionOutcome.make` sorts the request into missing, undeletable and deletable before the prompt. Afterwards items are settled as `deleted` or `undeletable`; missing ones are settled as `gone` **only under full access**. Just before settling, `deleteNow` records the deleted items in the cleanup history (`ProgressStoring.recordCleanup`), one entry per category, using the category saved with each decision (`StoredDecision.category`, from the card it was made on). Mock items are never recorded.
   Admin Tools' mock cards (debug builds, ids starting `admin-`, `LibraryItem.isAdminMock`) join the pile in memory only and count toward the free pile limit, but never cost a swipe. `saveProgress`, `settle` and `delete` each drop mock ids, so no mock decision reaches `ItemProgress` and no mock item reaches `library.delete`. Deleting them from the pile just drops them and counts their bytes as freed, so the post-delete offer can show; a mocks-only delete isn't counted toward the review prompt and keeps undo. "Remove mock cards" and the next launch clear them. Mock cards themselves still sit in the saved deck (`SessionProgress`) until the next launch strips them in `restore`, and a refill's `FrontLoad` can reorder queued mock cards behind the current one.
7. **External changes and restore.** `vanishedItems()` reports removed IDs while the app runs, and on launch `missing(from:)` checks the saved deck and pile. Under full access those items are settled as `gone` and removed from the index. Under limited access they may just be outside the selection, so they're only hidden (`outOfReachIDs`) and stay pending in the store. Either way they leave upcoming cards.
8. **Dashboard.** The Library tab shows `DashboardController`'s snapshot: the history plus `FeedBuilding.libraryScan` (the index's cached features and the last page's groups, no PhotoKit), summed by `DashboardStats` and cached as JSON in Caches. It refreshes when the tab shows and the snapshot is over 10 minutes old, on pull to refresh, and after each delete; refreshes coalesce, so one asked for mid-run runs again rather than reusing older numbers. On the main actor it reads only the history (and, once on the first V2 launch, the deleted rows it fills the history from); what to leave out comes from the view model's memory plus the builder's last page, never from every saved decision. The scan runs on the builder actor and the sums in a detached task.

## Persistence

| Store | What | Notes |
|---|---|---|
| `ItemProgress` | One row per decided asset: decision, settlement, page number, category (V2, optional), `LibraryItem` JSON | Unique by `itemID` (`PHAsset.localIdentifier`). `SwiftDataProgressStore` mirrors each row's decision, date and settlement in memory once the first page is built |
| `CleanupEvent` | The cleanup history (V2): time, category, count, bytes, one row per category per delete | Only added to, and cleared by a reset. Deletes made before V2 are filled in once, per day and category, from settled `ItemProgress` rows, so the history adds up to `freedBytes()` |
| `SessionProgress` | The current deck as JSON, plus index, marks and drafts | One row. A swipe that doesn't change the cards rewrites only index, marks and drafts (`DeckWrite.position`) |
| `AssetFeatureRecord` | Cached features and feature print (external storage) | Can be rebuilt from the library |
| UserDefaults | Allowance, onboarding, reminder log, dev tunables, cached unlock | Keys in `DefaultsKey` |
| Caches `dashboard-snapshot.json` | The last `DashboardSnapshot` | A cache: rebuilt by any refresh, safe to lose |

The models are versioned (`BristleSchemaV1`, `BristleSchemaV2`, `BristleMigrationPlan` with a lightweight V1→V2 stage); `BristleSchema.swift` has the steps for adding a version. V1's changed model is frozen as a nested type (`BristleSchemaV1.ItemProgress`); unchanged models are shared between versions. Stores written before versioning can have older layouts that staged migration refuses as an unknown version, so `makeContainer` then opens them without the plan, letting Core Data infer the lightweight migration as those builds did (found in JUN-9). A version that only adds `#Index` doesn't work: indexes don't change Core Data's version checksum, so SwiftData rejects the plan ("Duplicate version checksums detected") and the app aborts at launch (found in JUN-45). Saved JSON (`LibraryItem`, `Session`) must still decode older data, so new Codable fields are optional.

`PhotoKitFeedBuilder` keeps the index's records and its grouping work between pages until `FeatureIndex.generation` changes (`GroupingCache`). Feature prints are never kept in memory.

## Build variants

- **Debug.** Launch arguments are documented on `launch()` in `photo_swiperApp.swift`. Mocks and `MockAssets.xcassets` are available. Developer mode is on.
- **Release.** Mocks are compiled out. Developer mode exists only for TestFlight and Xcode installs (`DevMode`, via `AppTransaction`), never for App Store builds.

## Safety properties

Every change must keep these. Each names what guards it; run the guard after touching the area.

| Property | Guarded by |
|---|---|
| **Pile-only deletion.** A swipe only adds to the pile. The cleanup history only records what `deleteNow` actually deleted (`CleanupHistoryTests`). `PHAssetChangeRequest.deleteAssets` is called only in `PhotoKitLibrary.delete`, reached only from `PendingPileView` after its in-app alert, then iOS's prompt. Admin Tools' mock items never reach it, nor `ItemProgress` | The single call site (`pre-pr` greps for a second one). `AdminMockFeedTests` records `FakeLibrary.onDelete` and every store write: mock items are never passed to `delete` or saved. No unit test yet asserts a real swipe never calls `delete` |
| **Decisions bind to the card the user acted on** (`cardID` through `decide`, `decideIndividually`, `canDecide`, `refuse`). Focusing the feed never moves or replaces the current card | `CardIdentityTests`, `FeedFocusTests` |
| **`FrontLoad` never moves the current card** | `FrontLoadTests` (`theCardOnTopNeverMoves`) |
| **Limited access never settles items as `gone`** | `LimitedAccessTests` |
| **Write-through persistence.** Every mutating `ProgressStoring` call is durable when it returns | `ProgressWritesTests`, `ProgressStoreTests` |
| **Versioned schema.** Model changes go through `BristleSchema.swift` | `SchemaVersioningTests` (unversioned and V1 stores open as V2), `FeatureIndexStoreTests` (older index layouts) |
| **No new network use.** The only network calls go to Apple: iCloud downloads, StoreKit, and `CLGeocoder` with a ~1 km cell's centre (`PlaceNamer.Cell`), never a photo's own coordinate. The privacy copy ("approximate locations") depends on it | `PlaceNamerTests`; `pre-pr` greps for `URLSession`, `CLGeocoder` and `import Network` |
| **Mocks and debug switches stay in `#if DEBUG`.** Release never reads launch arguments or unlocks for free | `DevModeTests` for Developer mode; otherwise review (`pre-pr` checks the diff) |

## Decisions worth knowing (lightweight ADRs)

- **On-device only.** No accounts, analytics or crash SDKs. Apple is the only network peer (see Safety properties).
- **Write-through persistence.** Every decision is durable when `decide` returns, so force-quitting never loses work.
- **Pile, then confirm, then system prompt.** A swipe never deletes. That's the main safety property; keep it.
- **Limited access is not deletion.** Under `.limited`, "not found" may mean "not selected", so nothing is settled as `gone`.
- **Endless deck.** Pages are appended. Cards more than 30 behind (`keptBehind`) are trimmed, and their pending deletes carry on in the pile.
- **Index is resumable by diff, not cursor.** A cancelled run loses nothing.
