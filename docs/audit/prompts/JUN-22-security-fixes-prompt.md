# JUN-22 Security Fixes — Agent Prompt

> Recommended run settings: highest-reasoning model, high effort, plan mode first. Run it on the Mac with Xcode installed, from the `photo-cleaner` repo root.
> Attach `docs/audit/JUN-5-audit-report.md` as context.

---

## Owner decisions (fill in before running)

**S-2: what to do about place-name lookups.** Pick one; the agent stops and asks if this is blank.

- [ ] **A. Keep and disclose** *(recommended, smallest change)*: keep place names, but send only coarse (~1 km) coordinates, and change the copy so it no longer says "nothing is uploaded".
- [ ] **B. Opt-in**: add a Settings toggle "Show place names" (off by default). With it off, no coordinates leave the device. Copy updated to match.
- [ ] **C. Remove**: drop reverse geocoding entirely. Captions show no place name.

**S-5: move the feature index out of backups?** `[ ] yes` / `[ ] not now` (default: not now)

---

## Context

You're working on **Bristle**, a private, on-device photo-cleaner app for iOS 18+. It's written in Swift and SwiftUI, uses SwiftData and PhotoKit, and has no third-party dependencies.

Linear tracks the work under project *Bristle 1.0*, milestone *Beta*. The parent issue is **JUN-5 "Code Audit"**, and **your issue is JUN-22 "Security Risks"**.

A read-only audit found the issues below. The full report is attached; Part 1 (§3) has the evidence, file paths, line numbers and recommended fixes. **Line numbers refer to commit `706108e`, and the code may have moved since.** Re-locate everything by symbol before you edit.

Your job is to **implement the Part 1 fixes**, safely, with tests, as small reviewable PRs. A human merges them. You don't.

Before you start, read these, and treat their rules as binding:

- `docs/audit/drafts/CLAUDE.md` (rules and commands)
- `docs/audit/drafts/ARCHITECTURE.md` (how the app works)
- §2 of the report (the walkthrough)

## Ground rules

1. **Plan first.** Start in plan mode. Show the owner a short plan per finding: the files, the approach, the tests, and the PR boundaries. **Wait for approval** before editing. Every fix here touches deletion, permissions, persistence or privacy, so a human approves the approach once, up front.
2. **Prove the bug before fixing it.** For each behavioral finding (S-1, S-3, S-4, S-8), write the failing test first and confirm it fails on the current code. **If it passes before your fix, stop and report.** The finding may be wrong or already fixed. Don't "fix" something you can't reproduce.
3. **Stay in scope.** Fix only what's listed. Don't do Part 2 refactors (FeedViewModel decoupling, Swift 6, de-duplication). The one exception is the smallest seam a test needs; when you add one, say so in the PR.
4. **Never weaken the delete path.** The only route to `PHAssetChangeRequest.deleteAssets` stays: pile, then the in-app alert in `PendingPileView`, then `vm.deleteNow`, then `PhotoKitLibrary.delete`, then the iOS prompt. No new code path may delete, and no change may remove a confirmation.
5. **No new network use,** apart from what the S-2 decision explicitly keeps.
6. **Persistence stays write-through and backward-compatible.** Existing users' stores must open after your change. Saved JSON (`LibraryItem`, `Session`, `SavedSession`) must still decode.
7. **Verify every change** before you call it done:
   ```sh
   # pick a simulator: xcrun simctl list devices available
   xcodebuild -project photo-swiper/photo-swiper.xcodeproj -scheme photo-swiper \
     -destination 'platform=iOS Simulator,name=<device>' test -only-testing:photo-swiperTests
   ```
   Also run the UI tests for any flow you touched (feed swiping, pile, onboarding, settings). XcodeBuildMCP in `.mcp.json` is available as an alternative. Zero new compiler warnings in files you touched.
8. **Git and Linear:**
   - Branch from `main`, one branch and one PR per group below, named `jun-22-<slug>`.
   - Commit messages: `bug(security): <summary> [JUN-22]`.
   - Open PRs with `gh` and **don't merge**. Each PR description has "What / Why / How tested / Risk" and a "Needs human review" line.
   - When a PR is up, comment its link on JUN-22.
   - **Don't change issue statuses or create issues** unless the owner says so.
9. **Stop and ask** if you hit any of these:
   - the S-2 decision is blank;
   - a fix would need a data migration that drops or rewrites user data;
   - unrelated tests fail on `main` before you start;
   - a fix needs a change to the delete path beyond what's described here.

## Work, in order

Each group is one PR. For each one: write the failing test, then the minimal fix, then verify, then open the PR.

### PR 1 — S-1: decisions must apply to the card the user acted on (High)

**Problem.** `CardStackView.decide(_:card:)` ignores `card` and calls `vm.decide(direction)` / `vm.decideIndividually(outcome)`, which act on `vm.currentCard`. Meanwhile `refreshAllowance()` → `frontLoad()` → `FrontLoad.reordered(cards, from: index)` can move a different card into the current position. That reordering can be triggered in three places:

- the refill timer in `FeedView`'s `.task(id: vm.nextRefillAt)`;
- scene activation in `RootView`;
- inside `decide()` via `admitSwipe()`, after the card was already read.

**Fix — all three parts, as defense in depth:**

1. **Thread the card's identity through.** Change the VM intents to `decide(_ direction:, cardID:)` and `decideIndividually(_ outcome:, cardID:)`. Do the same for `canDecide`/`canDecideIndividually` where they read the current card. **If `currentCard?.id != cardID`, do nothing**: don't spend a swipe, don't write anything, and log in DEBUG. Update `CardStackView` (and any other caller, including `refused`/`saveDraft`) to pass the card it was given.
2. **`FrontLoad` must never move the card at `index`.** Front-load from `index + 1`, both in `frontLoad()` and when a page lands in `appendPage()`. A fresh deck in `apply()` can still reorder from 0. Update `FrontLoad`'s doc comment and its existing tests.
3. **In `decide()` and `decideIndividually()`,** run `admitSwipe()` (which may refresh the allowance) *before* reading the current card.

**Tests** (Swift Testing, with the mock library and an injected `now`):

- A deck of `[photo A, photo B, similar S]`, with the allowance below cap and a refill due. Call `refreshAllowance()`, then `decide(.left, cardID: A.id)`. Expect only A's item to be pending, S undecided, and A still at `index - 1` for undo.
- The same, but with the refill landing *during* `decide()` (clock advanced between deal and decide).
- `decideIndividually` with a batch card's outcome, after a reorder. Expect it to apply to the batch, never to the card now on top.
- A mismatched `cardID` is a no-op: no swipe spent, no store write.
- Undo after a front-load returns the right card (`returningCard.cardID` matches the restored card).

**Check:** existing UI tests (`SwipeRewindUITests`, `DuplicatesUITests`, the main UI suite) still pass.

### PR 2 — S-3 + S-10: limited photo access is not "deleted elsewhere" (Medium + Low)

**Problem.** Under `.limited` access, `PHAsset.fetchAssets(withLocalIdentifiers:)` only returns photos in the user's selection. So anything outside it gets settled as `.gone` in three places:

- `restore()` via `library.missing(from:)`;
- `delete()` via `outcome.missing`;
- the change observer, which fires when the selection shrinks.

Those items leave the pile without being deleted, and `excludedFromNewSession` hides them forever. `LibraryIndexer.run()` also deletes index records for every unselected asset.

**Fix:**

1. **Expose the current authorization.** Add `currentAccess() -> LibraryAccess` (it never prompts) to `PhotoLibraryProviding` and implement it in `PhotoKitLibrary` and `MockPhotoLibrary`. The mock gets a settable access value for tests.
2. **Only full access proves an item is gone.** Settle as `.gone` only when the current access is `.full`. Under `.limited`:
   - **Restore:** remove not-visible items from the deck and hide them from the pile *display*, but leave their store records open. They're still pending, just not visible.
   - **Delete:** not-visible items stay pending. Set `deleteNotice` to explain, for example: *"N items are outside the photos Bristle can access and weren't deleted."*
   - **Change observer:** don't settle removals at all. A removal may just be a selection change. Still prune not-visible cards ahead of the current card, as `forget` does today.
3. **`LibraryIndexer.run()` skips its prune step** (`index.remove(gone)`) unless access is full. The indexer needs the same access check, so pass a closure or the library in.
4. **One-time repair (guarded):** on a launch with **full** access, re-check records settled `.gone` whose asset still exists (one `fetchAssets` for those IDs). Reopen them: clear the settlement, so they return to the pile or feed as their decision says. Log the count. This only reopens records and never deletes anything.
5. **S-10, limited-access UX:**
   - On the Library tab's "Selected photos only" row, add "Add more photos", which calls `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)` (wrap it for SwiftUI). Keep the Settings link as the secondary option.
   - Add `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES` to `photo-swiper/Info.plist`.

**Tests:**

- Limited access + restore: pile items not visible stay pending in the store, `excludedFromNewSession` still behaves, and the items return when access flips to full.
- Limited access + `deleteNow` with a mix of visible and not-visible items: only visible ones are deleted. The rest stay pending and a notice is set.
- Limited access + a vanished event: nothing is settled.
- Full access + vanished event: settled `.gone`, as before. This is a regression test.
- The repair reopens wrongly-gone records under full access, and does nothing under limited access.
- Indexer under limited access: no records removed.

### PR 3 — S-4 (+ optional S-5): version the SwiftData schema (Medium)

**Fix:**

1. Add `enum BristleSchemaV1: VersionedSchema` with `versionIdentifier = Schema.Version(1, 0, 0)` and `models = [ItemProgress.self, SessionProgress.self, AssetFeatureRecord.self]`. Those are today's models, **unchanged**.
2. Add `enum BristleMigrationPlan: SchemaMigrationPlan` with `schemas = [BristleSchemaV1.self]` and no stages.
3. Build the container with `ModelContainer(for: Schema(versionedSchema: BristleSchemaV1.self), migrationPlan: BristleMigrationPlan.self, configurations: …)` in `SwiftDataProgressStore.makeContainer`.
4. **Existing on-disk stores must open with no data change.** Prove it with a test (below) before touching anything else.
5. **Surface open failures in Release.** If the container can't open, keep the in-memory fallback, but set a flag the UI shows once ("Couldn't load your saved progress. Your photos are untouched."). Keep `assertionFailure` for Debug.
6. Add a short comment block in the schema file: how to add V2 and a migration stage, and the rule "new fields optional, or add a stage".

**Tests:**

- Create a store at a temp URL with the *pre-change* `makeContainer` path (bare models). Write decisions and a session. Reopen it with the versioned container, and expect everything readable.
- The versioned container round-trips.
- Optional: check in a tiny V1 `.store` fixture for future migration tests.

**S-5 (only if the owner ticked yes).** Move `AssetFeatureRecord` to its own `ModelConfiguration`, at a URL under Application Support, and exclude that file from backup (`URLResourceValues.isExcludedFromBackup = true`, re-applied at each launch). The index can be rebuilt, so the old index table may simply be abandoned. **Don't migrate it, and don't touch progress data.** Put this in a separate commit inside PR 3 so it's easy to revert.

### PR 4 — S-2: place-name lookups (High), following the owner's decision

**All options:**

- Update every "nothing is uploaded" / "never uploaded" claim so it is true:
  - `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` in **both** Debug and Release configurations in `project.pbxproj` (edit carefully; change only that value);
  - the Settings "About" row (`SettingsView`);
  - any onboarding copy that says the same.
- `AppInfoTests.photoUsageStringNamesTheApp` must still pass.
- In the PR description, include suggested privacy-policy wording for the website (a separate repo; don't edit it).

**A. Keep and disclose:**

- In `PlaceNamer`, look up the **cell center** (`CLLocation(latitude: Double(cell.lat) / 100, longitude: Double(cell.lon) / 100)`), never the photo's exact coordinate.
- Add a test that the location passed to the geocoder equals the cell center. Introduce a tiny `Geocoding` protocol so this can be tested without the network.
- Suggested copy: usage string *"Bristle looks through your library on this iPhone to find photos you may want to clear. Your photos never leave your iPhone."* Settings: *"Your photos are analyzed on this iPhone and never leave it. Place names are looked up with Apple using approximate locations."* Adjust the wording if needed, but stay accurate.

**B. Opt-in:** everything in A, plus a `showPlaceNames` preference, off by default, in Settings › Feed. When it's off, `PhotoKitFeedBuilder` must not call `PlaceNamer` at all; pass `placeBudget = .zero` or skip the call. Add a test that with it off, the geocoder is never called.

**C. Remove:** delete `PlaceNamer` and the CoreLocation import. `LibraryItem.location` stays optional and becomes nil for new items, so old saved items still decode. Captions handle nil already; check the card views.

### PR 5 — small items: S-8, S-7, S-6

- **S-8, `VideoSource`:** protect `RequestBox.id` with a lock. Make the continuation resume exactly once, including on cancellation (resume with `nil` from `onCancel` via a once-only flag, the same pattern as `Once` in `PhotoKitIndexSource`). Add a unit test with a fake request API if a seam is cheap; otherwise explain in the PR why it isn't covered.
- **S-7, copy:** "Large libraries keep scanning in the background" → "Large libraries keep scanning while you swipe." (`PhotoAccessPrimerView`). Update any UI test that matches the old string.
- **S-6, `FileSizeReader`:** no behavior change. Add a DEBUG-only log the first time the `fileSize` key returns nil, so a future iOS change is noticed. Mention in the PR that this is undocumented KVC.

**Not in scope:** S-9 (no change needed); A-4 (pinning `.mcp.json`) belongs to JUN-23.

## When you're done

Reply to the owner with:

1. A table with one row per finding (S-1 … S-10): status (fixed / partly fixed / not reproduced / skipped), PR link, tests added, and anything left for a human to check.
2. The one manual on-device check per PR the owner should do before merging. For example, for PR 1: open a photo full screen with the free-swipe timer set to `-refillSoon YES`, wait for the refill, swipe, and confirm the right photo landed in the pile.
3. Anything you found that the audit missed, as a short list, without fixing it.

Before replying, re-read every diff on the delete path and confirm in one sentence per PR that no new deletion route or skipped confirmation exists.
