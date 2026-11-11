---
name: pre-pr
description: Use before opening any pull request in this repo, and before saying a branch is ready. Runs make verify (plus UI tests when views or FeedViewModel changed), checks the diff against main for privacy, safety and doc-drift problems, gets a fresh-context review for sensitive changes, and drafts the PR body.
---

# Before opening a PR

1. **Checks.** Run `make verify` (outside the Bash sandbox). If the diff touches `Views/` or `FeedViewModel*.swift`, also run `make test-ui`, alone. Rerun a UI failure in isolation before calling it a regression or a flake.
2. **Diff review** against main: `git diff origin/main...HEAD` plus uncommitted changes. Report each hit with file and symbol, then fix it or justify it:
   - [ ] a new `print(`;
   - [ ] `privacy: .public` on an identifier, place name or file name outside `#if DEBUG`;
   - [ ] mocks, launch-argument reads or debug unlocks outside `#if DEBUG`;
   - [ ] new network use: `URLSession`, `import Network`, `CLGeocoder`, `isNetworkAccessAllowed = true`, or any SDK;
   - [ ] a second `PHAssetChangeRequest.deleteAssets` call site (`git grep -n deleteAssets` must show only `PhotoKitLibrary`);
   - [ ] an `@Model` change (`ProgressModels.swift`, `AssetFeatureRecord.swift`) without a `BristleSchema.swift` change, or a new non-optional Codable field on saved JSON;
   - [ ] a new `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it's safe;
   - [ ] a sensitive path touched (the list in `scripts/hooks/guard-sensitive-paths.sh`) without "Needs human review" in the PR body;
   - [ ] Swift files added, removed or renamed under `Services/`, `ViewModels/` or `Models/`, or a data-flow change, without an `ARCHITECTURE.md` update;
   - [ ] non-code files added under `photo-swiper/photo-swiper*/` (they ship in the bundle);
   - [ ] `Views/` or `DesignSystem/` changed without a `ui-review` pass (run it and resolve its blockers), or a token or component changed without a `DESIGN.md` update.
3. **Sensitive paths.** If one changed, load `privacy-destructive-guard` and put its proof for each affected property in the PR, then run the `reviewer` subagent on the branch and address what it finds.
4. **PR body.** Fill `.github/pull_request_template.md`: What / Why / How tested (paste the `make verify` summary lines) / Risk, the human-review checkbox, the ARCHITECTURE checkbox, and the Linear issue. Title: `feat|bug|chore|perf(scope): summary [JUN-NN]`.
