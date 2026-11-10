# PhotoKit — local rules

This is the only code that touches the user's real library, and the only place that deletes. **Every change here needs human review**; say so in the PR.

- **`PhotoKitLibrary.delete` is the only caller of `PHAssetChangeRequest.deleteAssets`.** Never add another, and never call it from a swipe path. It's reached only from `PendingPileView`, after the in-app alert. iOS then shows its own prompt.
- **Limited access:** "not found" may mean "not selected". Only `.full` from `currentAccess()` lets anything be treated as gone. Keep `missing(from:)` and `vanishedItems()` reporting raw facts, and leave the settling to `FeedViewModel` (`LimitedAccessTests`).
- **No new network calls.** `PlaceNamer` sends only a ~1 km cell's centre (`PlaceNamer.Cell`) to `CLGeocoder`, never a photo's own coordinate. The privacy copy in Settings says "approximate locations". Only display (`ThumbnailPipeline`, `VideoSource`) may download from iCloud; analysis (`PhotoKitIndexSource`) never does.
- Pure decisions belong in testable functions (like `DeletionOutcome.make`). Keep PhotoKit calls thin, behind `PhotoLibraryProviding`, `AssetCatalog` and `Geocoding`, so tests use fakes.
- PhotoKit isn't reachable from unit tests. Check changes on a simulator with photos in it, and say how in the PR.
