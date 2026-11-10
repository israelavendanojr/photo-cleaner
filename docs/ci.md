# CI and local checks

CI (`.github/workflows/ci.yml`) runs on every pull request to `main`:

| Job | What it does | Fails the PR? |
|---|---|---|
| `test` | Builds the app and test targets, then runs the unit tests (`photo-swiperTests`), skipping the three below | Yes |
| `lint` | Runs SwiftFormat (lint mode) and SwiftLint on the Swift files the PR changes | No, warnings only |

CI skips three unit tests that only work on a real Mac, so run them locally:

- `ScalingTests`: benchmarks over 50,000 synthetic items. They're slow, and their numbers are only meaningful on known hardware.
- `StoreKitEntitlementStoreTests`: StoreKitTest sessions hang on hosted runners, so every test hits its time limit.
- `FeaturePrintTests/distanceMatchesVision()`: this compares against live Vision, whose prints differ on virtualized runners.

UI tests (`photo-swiperUITests`) don't run in CI. Run them locally before merging anything that touches views or `FeedViewModel`.

## Running the same checks locally

Pick a simulator with `xcrun simctl list devices available`, then:

```sh
# Unit tests, as CI runs them
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:photo-swiperTests -skip-testing:photo-swiperTests/ScalingTests \
  -skip-testing:photo-swiperTests/StoreKitEntitlementStoreTests \
  '-skip-testing:photo-swiperTests/FeaturePrintTests/distanceMatchesVision()'

# Everything, the way to run it on your Mac before merging
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:photo-swiperTests

# UI tests (slow; run alone, with nothing else building, and with -parallel-testing-enabled NO)
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' -parallel-testing-enabled NO \
  test -only-testing:photo-swiperUITests

# Scaling benchmarks (50k synthetic items; prints timings to the test log)
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:photo-swiperTests/ScalingTests
```

## Lint and format

Both are dev tools only, never linked into the app: `brew install swiftlint swiftformat`.

```sh
swiftformat --lint .          # what would change; config in .swiftformat
swiftlint lint                # config in .swiftlint.yml

# Only the files your branch changed, as CI does
git diff --name-only --diff-filter=ACMR origin/main...HEAD -- '*.swift' | xargs swiftformat --lint
git diff --name-only --diff-filter=ACMR origin/main...HEAD -- '*.swift' | xargs swiftlint lint
```

Nothing is auto-corrected. To format a file you're already changing, run `swiftformat <file>`. Don't reformat files you aren't otherwise touching.

`unused_import` is an analyzer rule, so it needs a compile log:

```sh
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build > build.log
swiftlint analyze --compiler-log-path build.log
```
