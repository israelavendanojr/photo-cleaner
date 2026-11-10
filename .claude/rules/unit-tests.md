---
paths:
  - "photo-swiper/photo-swiperTests/**"
---

# Unit tests — local rules

- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`), never XCTest here. `@MainActor struct` suites; parameterize with `@Test(arguments:)`, e.g. `ProgressStoreTests.Kind.allCases` to run against both stores.
- **No PhotoKit.** Use the fakes in `photo_swiperTests.swift` (`FakeLibrary`, `TestEntitlements`, `freshDefaults()`), the app's `Services/Mock/` (`MockFeedBuilder`, `InMemoryProgressStore`), `SwiftDataProgressStore.inMemory()`, and `SyntheticLibrary` for made-up features. `FeedBuilderTests` shows fakes for `AssetCatalog` and `Geocoding`.
- **Time is injected.** Pass `now:` to `FeedViewModel` (and the collaborators that take it) with a fixed date. Never depend on the wall clock.
- **Swipes:** `FeedViewModel+TestSwipes.swift` swipes whatever card is on top (`decideCurrent`). `CardIdentityTests` names cards explicitly; do the same when a test is about which card a decision hits.
- **No second `@Model` with an app model's class name**, even in a test: SwiftData resolves models by name process-wide and unrelated tests crash. Build old-format stores with a plain Core Data model (see `FeatureIndexStoreTests`).
- **CI skips three tests** (`SKIP_CI` in the `Makefile`; why in `docs/ci.md`): `ScalingTests` (50k-item benchmarks, local only: `make test-scaling`), `StoreKitEntitlementStoreTests` (hang on hosted runners and can flake locally), and `FeaturePrintTests/distanceMatchesVision()` (live Vision differs on virtual machines). Run `make test-all-unit` on your Mac when you touch those areas.
- **Reading failures:** Swift Testing's messages don't reach xcodebuild's summary. The full log is in `build/logs/test-unit.log`; for details, rerun with `-resultBundlePath` and read it with `xcrun xcresulttool get test-results tests --path <bundle>`.
- Run tests outside the Bash sandbox, or codesigning silently fails and the test host won't launch.
- UI tests (`photo-swiperUITests`, XCTest) run serially with `make test-ui`, alone, with nothing else building. Under load they flake.
