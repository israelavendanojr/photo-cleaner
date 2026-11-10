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

CI calls the root `Makefile`, so these are the same checks. Run `make` alone to list the targets.

```sh
make verify         # lint + build + unit tests as CI runs them. Run it before saying a change is done.
make build          # incremental build of the app and test targets; errors only (full log: build/logs/build.log)
make test-unit      # unit tests with CI's three skips
make test-all-unit  # every unit test, nothing skipped (do this on your Mac before merging)
make test-ui        # UI tests, serially; slow, so run them alone with nothing else building
make test-scaling   # the 50k-item benchmarks; timings land in build/logs/test-scaling.log
```

- The simulator is the first available iPhone (`scripts/sim-destination.sh`, the same pick as CI). Set `DEST='platform=iOS Simulator,name=iPhone 16'` to choose one.
- Builds go to `build/DerivedData` in the repo, not Xcode's shared folder, so each worktree builds on its own. `make clean` removes it.
- The skip list lives once, in `SKIP_CI` in the `Makefile`.

## Lint and format

Both are dev tools only, never linked into the app: `brew install swiftlint swiftformat`.

```sh
make lint       # both linters on the Swift files changed against origin/main (BASE=…); warnings only
make lint LINT_STRICT=1   # the same, but fail on findings
make format     # SwiftFormat on the changed files only
make lint-all   # the whole tree; informational
make analyze    # swiftlint analyze (unused_import), from a fresh build log
```

Configs: `.swiftformat` and `.swiftlint.yml`. `make format` only touches files your branch changed. Don't reformat files you aren't otherwise touching.

## The raw commands

What the targets run, for when you need a flag they don't expose:

```sh
xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:photo-swiperTests -skip-testing:photo-swiperTests/ScalingTests \
  -skip-testing:photo-swiperTests/StoreKitEntitlementStoreTests \
  '-skip-testing:photo-swiperTests/FeaturePrintTests/distanceMatchesVision()'
```

UI tests need `-parallel-testing-enabled NO`: parallel runs use cloned simulators where the test runner fails to launch.
