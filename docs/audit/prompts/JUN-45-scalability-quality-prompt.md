# JUN-45 Scalability & Code Quality — Agent Prompt

> Recommended run settings: highest-reasoning model, high effort, plan mode first. Run it on the Mac with Xcode installed, from the `photo-cleaner` repo root.
> Attach `docs/audit/JUN-5-audit-report.md` as context.

---

## Owner decisions (fill in before running)

| # | Question | Options | Default if blank |
|---|---|---|---|
| D1 | Add CI on GitHub Actions? macOS runners use more of a private repo's free minutes. | `[ ] yes` / `[ ] no` | **yes**: build plus unit tests on each PR, no UI tests |
| D2 | How far should concurrency hardening (Q-5) go? | `[ ] complete checking, stay in Swift 5 mode` / `[ ] switch to Swift 6 mode too` | **complete checking only** |
| D3 | Run a whole-repo formatting pass once SwiftFormat is added? | `[ ] yes, as the very last PR` / `[ ] no, format only touched files` | **no** |
| D4 | Branch and worktree cleanup (Q-8) | `[ ] agent deletes merged local branches and prunable worktrees` / `[ ] agent only lists the commands` | **only lists the commands** |

---

## Context

You're working on **Bristle**, a private, on-device photo-cleaner app for iOS 18+. It's written in Swift and SwiftUI, uses SwiftData and PhotoKit, and has no third-party dependencies.

Linear tracks the work under project *Bristle 1.0*, milestone *Beta*. The parent issue is **JUN-5 "Code Audit"**, and **your issue is JUN-45 "Scalability & Code Quality"**.

The attached audit report's **Part 2 (§4)** lists the findings Q-1 to Q-10, with evidence and recommended fixes. §2 has a walkthrough of how the app works.

Your job is to **implement the Part 2 fixes**, safely, with tests, as small reviewable PRs. A human merges them. You don't.

### What changed since the audit (read before planning)

The audit was taken at `706108e`. The JUN-22 security fixes (PRs #19–#23) have merged since, and they affect this work:

- **Swipe decisions now carry a card ID.** `decide`, `decideIndividually`, `canDecide…` and `refuse` all take `cardID`, and use a `currentCard(matching:)` helper. `FrontLoad` never moves the card at `index`. **This is a safety property. Preserve it through every refactor.** `CardIdentityTests` and `FrontLoadTests` must keep passing unchanged.
- **The schema is versioned.** `Services/Persistence/BristleSchema.swift` has `BristleSchemaV1` and `BristleMigrationPlan`, plus written steps for adding V2. **Any model change, including adding `#Index`, follows those steps**, with a test that opens a V1 store.
- **Limited access has its own rules.** `PhotoLibraryProviding` gained `currentAccess()` and `presentLimitedPicker()`. `missing(from:)` reports items outside a limited selection; items are settled as `gone` only under full access (`LimitedAccessTests`).
- **`PlaceNamer` already has a `Geocoding` seam.** Q-4 only needs the asset-catalog seam and the deletion-outcome extraction.
- **`FeedViewModel` is now 1,208 lines**, still with 23 members marked `// internal for FeedViewModel+…`.
- **There's still no Makefile, `CLAUDE.md`, lint config or CI in the repo.** JUN-23 is separate work. If `CLAUDE.md`, `ARCHITECTURE.md` or a `Makefile` land at the root before or during your run, follow them. Until then, treat `docs/audit/drafts/CLAUDE.md` and `docs/audit/drafts/ARCHITECTURE.md` as the binding rules.

**Line numbers in the report are stale.** Re-locate everything by symbol, and **re-check each finding against current `main` before planning it**. If one no longer holds, say so and skip it.

## Ground rules

1. **Plan first.** Start in plan mode. Show the owner a short plan per PR: the findings it covers, the files, the approach, the tests, and the risk. **Wait for approval** before editing. Point out any place where the plan touches deletion, decision binding, persistence or the schema.
2. **Behavior doesn't change unless the finding is about behavior.** Q-3, Q-4, Q-5, Q-6 and Q-9 are refactors: the existing test suite (about 430 unit tests plus the UI tests) must pass **without editing assertions**. Only call sites and signatures may change. If an assertion has to change, stop and explain why in the PR.
3. **Measure before and after for performance work** (Q-1, Q-2, Q-10). Put the numbers in the PR. Never trade correctness for speed: a cached result must be identical to an uncached one.
4. **The safety properties from JUN-22 are off-limits.**
   - The only route to `PHAssetChangeRequest.deleteAssets` stays: pile, then the alert in `PendingPileView`, then `vm.deleteNow`, then `PhotoKitLibrary.delete`, then the iOS prompt.
   - Decisions bind to the card ID.
   - `FrontLoad` never moves the current card.
   - Limited access never settles items as `gone`.
   - Persistence stays write-through: every decision is durable when `decide` returns.
5. **No new dependencies** in the app. SwiftLint and SwiftFormat are dev tools only: install them with Homebrew, or pin them in CI. Never link them into the app target.
6. **Verify every change** before you call it done:
   ```sh
   # pick a simulator: xcrun simctl list devices available
   xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
     -destination 'platform=iOS Simulator,name=<device>' test -only-testing:photo-swiperTests
   ```
   Run the UI tests (`-only-testing:photo-swiperUITests`) for any PR that touches views or `FeedViewModel`. XcodeBuildMCP in `.mcp.json` is available as an alternative. Zero new compiler warnings in files you touched.
7. **Git and Linear:**
   - One branch and one PR per group below, named `jun-45-<slug>`.
   - Commit messages: `chore(quality): …` or `perf(feed): … [JUN-45]`.
   - **Work sequentially.** Branch from the latest `main`. If the previous PR isn't merged yet, stack on its branch and say so at the top of the PR.
   - Open PRs with `gh` and **don't merge**. Each PR description has "What / Why / How tested / Numbers (if perf) / Risk".
   - When a PR is up, comment its link on JUN-45.
   - **Don't change issue statuses or create issues** unless the owner says so.
8. **Stop and ask** if you hit any of these:
   - an owner decision you need is blank and has no default;
   - a change needs a schema migration that isn't purely lightweight;
   - an existing test fails on `main` before you start;
   - a refactor would need an existing test's assertion to change;
   - the measured gain for Q-1 is too small to justify the complexity (see PR 2).

## Work, in order

### PR 1 — Q-7: CI and lint/format config (Low, but it unblocks everything after it)

Doing this first means every later PR gets checked automatically.

- **If D1 is yes:** add `.github/workflows/ci.yml` on a macOS runner. Pin an Xcode version that builds iOS 18 (`sudo xcode-select -s /Applications/Xcode_<ver>.app`). Pick the simulator by querying `xcrun simctl list` rather than hard-coding a model name. Cache DerivedData if it's cheap. Run build plus `-only-testing:photo-swiperTests` on pull requests to `main`. No UI tests in CI.
- **SwiftFormat:** add `.swiftformat` matching the current style. Infer it from the code: 4-space indent, trailing commas in multi-line literals, long lines tolerated (about 140 columns), `self.` only where required. Run `swiftformat --lint` and report how many files would change. **Don't reformat** unless D3 is yes; then do it as the last PR.
- **SwiftLint:** add `.swiftlint.yml` with a **minimal** rule set. Start from `disabled_rules` for anything noisy on this codebase (line length, type body length, file length, identifier name). Keep `force_try`, `force_cast` with an inline exception at `VideoPreviewView.layerClass`, and `unused_import`. Lint only, no autocorrect.
- In CI, run both tools in lint mode on **changed files only**, as a warning (don't fail the build) for this first pass.
- Add a short `docs/ci.md` covering how to run the same checks locally. JUN-23 may later fold it into a Makefile.

### PR 2 — Q-1: stop rebuilding every page from the whole library and index (High)

**Measure first.**
- Add `OSSignposter` intervals around `PhotoKitFeedBuilder.makeSession` and its stages: library enumeration, `index.indexed()`, duplicate grouping, similar grouping (including loading feature prints), planning, and place names. Keep the existing `feed` log line.
- Add a **synthetic scaling test**, the report's §4.8 #5. Generate 50,000 `RankCandidate`s with realistic time clustering (bursts and sessions), dHashes and 768-float prints. Run `DuplicateGrouper`, `SimilarGrouper` and `SessionPlanner` under a `.timeLimit` and record the timings in the PR. Put it in its own suite tagged so CI can skip it if it's slow.
- Write down the before numbers: synthetic timings, plus an estimate of the bytes of prints loaded per page at 50k photos.

**Then fix:**
1. **Index generation counter.** `FeatureIndex` keeps a monotonically increasing `generation`, bumped by `upsert`, `updateHashes` and `remove`. Expose it through `FeatureIndexReading`.
2. **Cache the expensive, page-independent parts in `PhotoKitFeedBuilder`,** keyed by `(generation, skipFavorites)`:
   - the indexed-features dictionary;
   - the duplicate groups (`PlannedGroup`s) over **all** indexed candidates;
   - the similar groups over **all** indexed candidates.
3. **Per page,** filter the cached groups and candidates by `options.excluding`. A cached group with any member excluded is handled exactly as the current code would handle it. **Check how the current code handles partially decided groups, and preserve that behavior.** Then rank and plan as today.
4. **Don't keep prints after grouping.** Load feature prints only on a cache miss, and release them as soon as the groups are built.
5. **Library enumeration stays live** (favorites and membership change), but it should be the only full pass per page.

**Correctness test (required).** For several synthetic libraries and exclusion sets, a builder with a warm cache and a builder with a cold cache produce **identical** `Session.cards`, the same IDs in the same order. Also test that a `generation` bump invalidates the cache, and that toggling `skipFavorites` does too.

**Expected outcome.** Per-page print loading drops to near zero on a warm cache, and page time is dominated by library enumeration and ranking. Put the after numbers in the PR. If the gain is under about 2× on the synthetic 50k benchmark, stop and report instead of shipping the cache.

### PR 3 — Q-2: per-swipe persistence on the main thread (Medium)

1. **Indexes via schema V2.** Follow the steps in `BristleSchema.swift` exactly:
   - freeze V1 as nested types;
   - add `BristleSchemaV2` with `#Index<ItemProgress>([\.decisionRaw], [\.settlementRaw], [\.decidedAt])`;
   - add a `.lightweight(fromVersion: V1, toVersion: V2)` stage;
   - make the top-level names typealiases to the V2 types;
   - add a test that a V1 store opens and reads correctly with the V2 container. Extend `SchemaVersioningTests`.

   If SwiftData won't accept `#Index` as a lightweight change, **stop and ask**. Don't write a custom migration.
2. **One save per swipe.** Add `ProgressStoring.commit(decisions:session:)`, or an equivalent batch, so a swipe writes its decisions and the deck in **one** `context.save()`. Implement it in `InMemoryProgressStore` too, and use it from `FeedViewModel.commit`. **Write-through stays:** everything is saved before `decide` returns.
3. **Don't re-encode an unchanged deck.** Keep a `cardsRevision` counter on the VM, bumped whenever `session.cards` changes (`apply`, `appendPage`, `trimBehind`, `forget`, `frontLoad`). Re-encode the deck JSON only when it changed. When only `index`, marks or drafts change, update just those columns. **Don't debounce;** the deck must resume exactly after a force-quit.
4. **`reviewedCount()`** should rely on the new index. Don't keep a separate running count unless measurement shows the indexed `fetchCount` is still slow.
5. **Measure.** Add a test that runs about 200 decisions against an on-disk store pre-filled with 50,000 `ItemProgress` rows, and record the per-swipe time before and after. Existing `PersistenceTests` and `ProgressStoreTests` must pass unchanged.

### PR 4 — Q-4: PhotoKit seams so session assembly and deletion mapping are testable (Medium)

1. **Extract `DeletionOutcome.make(requested:found:deletable:)`** as a pure function from `PhotoKitLibrary.delete`. It must still respect the limited-access rules from JUN-22, so check how `delete` uses `currentAccess()` now. Unit-test it with mixed found, missing, undeletable and limited-access inputs. **The `performChanges` / `deleteAssets` call stays exactly where and as it is.**
2. **Add an `AssetCatalog` protocol** for what the feed builder needs from PhotoKit:
   - enumerate the library with fetch options, returning lightweight entries (ID, modified date, favorite);
   - look up features and locations by ID;
   - build a `LibraryItem` from an ID.

   Add `PhotoKitAssetCatalog` as the real implementation and a fake in tests. Inject it into `PhotoKitFeedBuilder` with a default, so `photo_swiperApp` doesn't change.
3. **Test `makeSession` end to end** with the fake catalog, a fake `FeatureIndexReading` and a fake `Geocoding`. Cover: grouped photos never also appear as singles; excluded IDs never appear; group IDs are stable across sessions; screenshot batches respect `minBatch` and `maxBatch`.
4. **Optional, only if trivial after step 2:** route `PhotoKitIndexSource.metadata` and `ThumbnailPipeline.asset(for:)` through the same fetch-by-IDs helper. Otherwise leave them for PR 6.

### PR 5 — Q-3: finish the FeedViewModel decoupling (Medium)

Behavior must not change (ground rule 2). Keep `FeedViewModel` as the one object views read.

1. **Hoist the nested enums.** Move `FeedViewModel.Phase`, `PaywallStatus` and `OnboardingStep` (plus `ReturningCard` and `DeleteChip` if that helps) to top-level types. Drop the typealiases in `SwipeGate` and `OnboardingFlow` that point back at `FeedViewModel`, which removes the type cycle. Leave `typealias`es on `FeedViewModel` only if they're needed to keep call sites small.
2. **Re-narrow the 23 `// internal for FeedViewModel+…` members.** Stored state becomes `private(set)` at least. Give the extensions narrow intents instead (for example `adminInsert(_ card:)` or `adminReset()`). **`session`, `index`, `settledIDs` and `returningCard` must not be settable from outside the class.**
3. **Move Admin Tools into `AdminController`** (`@MainActor`), which holds the VM and calls those intents. Settings reads it from the VM, e.g. `vm.admin`, or from the environment. Keep its `#if DEBUG` boundaries exactly as they are now.
4. **Collapse the duplicate designated inits.** The preview/"already loaded" init calls the main init, then `apply(session)` and `refreshTotals()`.
5. **Report the result:** line counts before and after, and the number of forwarders left. The target is a smaller `FeedViewModel` with no settable externally visible state. It doesn't need to reach a specific line count.

### PR 6 — Q-6 + Q-10 + Q-9: de-duplication and small fixes (Low / Nit)

Behavior must not change. Each item below is a separate commit.

- **`PHAsset.byID(_:)`**, or reuse the PR 4 helper, for the fetch-then-enumerate pattern. Replace every call site listed in report §4.4 that's still present.
- **`GroupingUtil.balancedChunks(_:max:)` and an oldest-first sort** shared by `SimilarGrouper` and `DuplicateGrouper`.
- **`stableGroupID(prefix:ids:)`** replacing `similarID` / `duplicateID`. **The output must be byte-identical**, because saved marks key on it. Add a test that pins a few known IDs.
- **A `KeeperGroup` protocol** (`items`, `keeperID`, `reason`, `others`) adopted by `SimilarGroup` and `DuplicateGroup`. Use it to collapse the parallel arms in `FeedViewModel` (`markedForClearing`, `completed`, `itemDecisions`, `removing`). **Don't change the `Codable` shapes.** Saved decks must still decode, so add a round-trip test from a JSON fixture of the current format.
- **Optional:** merge `SimilarShotsCardView` and `DuplicatesCardView` into one `KeeperGroupCardView`, **only if** the UI tests and a manual screenshot comparison show no visual change. If you skip it, say so.
- **`OpenSettingsButton`** (or an env helper) for the three "open iOS Settings" sites.
- **`Logger.app(category:)`** with one subsystem constant, replacing the hard-coded string in every file.
- **Q-10:** `ThumbnailPipeline.preheat` fetches all missing assets for the window in one `fetchAssets` call.
- **Q-9:** remove the `items[0]` fallback in `SimilarGroup.best` / `DuplicateGroup.keep`. Make it an optional, or guarantee non-empty at construction with a `precondition` covered by tests, and follow the compiler through the call sites.

### PR 7 — Q-5: concurrency hardening (Medium), following D2

1. Set `SWIFT_STRICT_CONCURRENCY = complete` on the app and test targets, then build and **list every warning** in the PR description, grouped by file.
2. **Fix the warnings.** Priorities:
   - **Make `FeatureIndex` a `@ModelActor`.** Keep its public API, and check that `LibraryIndexer` and the builder still work.
   - **Revisit every `@unchecked Sendable` and `nonisolated(unsafe)`.** Remove each one that can become properly `Sendable` (immutable, or isolated to an actor). For each one you keep, add a one-line justification comment saying which lock protects which state. The known ones are `PhotoKitLibrary`, `PhotoKitIndexSource`, `AnalysisImage`, `AnalysisCost`, `Once`, `VideoSource`'s request box, `CLGeocoding`, and `StoreKitEntitlementStore.updates`.
   - **Don't add `@preconcurrency` or `nonisolated(unsafe)` just to silence a warning.** If a warning can't be fixed cleanly, leave it, and list it with the reason.
3. **If D2 = "switch to Swift 6 mode too":** after the warnings are at zero, set `SWIFT_VERSION = 6.0` in a final commit. Run the full unit **and** UI test suites.
4. **This PR needs extra care:** it touches nearly every service. Keep each file's changes mechanical, and call out any change that alters *when* code runs (for example, moving work onto or off the main actor).

### PR 8 — Q-8: identity and hygiene (Low)

- Add a "Names" table to `docs/audit/drafts/ARCHITECTURE.md`, and to the root copy if it exists by then: repo `photo-cleaner`, project and scheme `photo-swiper`, module `photo_swiper`, permanent bundle ID, display name `Bristle`. **Don't rename the bundle ID, product ID, module or project.** Renaming the scheme is optional; ask first.
- **Branches and worktrees, following D4.** List the merged local branches, the merged remote branches, and the prunable worktrees (`git worktree list` shows `photo-cleaner-jun22-pr3/4/5` as prunable). Under the default, print the exact cleanup commands for the owner. **Never delete remote branches** without explicit approval.

## When you're done

Reply to the owner with:

1. A table with one row per finding (Q-1 … Q-10): status (done / partly done / no longer applies / skipped), PR link, tests added, and before/after numbers where measured.
2. The new `FeedViewModel` line count and forwarder count, the remaining `@unchecked Sendable` list with justifications, and the lint and format status.
3. One manual check per PR the owner should do before merging. For example, for PR 2: on a device with a large library, run with Instruments' os_signpost track and compare page build time to `main`.
4. Anything you found that the audit missed, as a short list, without fixing it.

Before replying, re-run `CardIdentityTests`, `FrontLoadTests`, `LimitedAccessTests` and `SchemaVersioningTests` on the final branch. Confirm in one line that the JUN-22 safety properties still hold.
