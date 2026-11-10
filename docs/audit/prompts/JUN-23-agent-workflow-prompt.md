# JUN-23 Agentic Workflow Setup — Agent Prompt

> Recommended run settings: highest-reasoning model, high effort, plan mode first. Run it on the Mac with Xcode installed, from the `photo-cleaner` repo root.
> Attach `docs/audit/JUN-5-audit-report.md` as context. Part 3 (§5) is the brief for this work.

---

## Owner decisions (fill in before running)

| # | Question | Options | Default if blank |
|---|---|---|---|
| D1 | Which agent instruction file is canonical? | `[ ] CLAUDE.md only` / `[ ] AGENTS.md canonical, CLAUDE.md imports it` (for Codex, Cursor and other tools too) | **CLAUDE.md only** |
| D2 | Run a build at the end of every agent turn that changed Swift files (`Stop` hook)? It adds about 30–90 s per turn. | `[ ] yes` / `[ ] no` | **yes** |
| D3 | Commit the audit report and the fix prompts to the repo under `docs/audit/`? | `[ ] yes` / `[ ] no, keep them local` | **yes** |
| D4 | Should CI call the new `make` targets, so local checks and CI can't drift apart? | `[ ] yes` / `[ ] no, leave ci.yml alone` | **yes** |

---

## Context

You're working on **Bristle**, a private, on-device photo-cleaner app for iOS 18+. It's written in Swift and SwiftUI, uses SwiftData and PhotoKit, and has no third-party dependencies. The owner builds it mainly with AI agents (Claude Code).

Linear tracks the work under project *Bristle 1.0*, milestone *Beta*. The parent issue is **JUN-5 "Code Audit"**, and **your issue is JUN-23 "Architecture.md & Agent.md files"**.

The JUN-5 audit graded agent readiness **D**. Your job is to make the repo something an agent can work in safely and check its own work in. That means:

- instruction and context files;
- a command-line feedback loop;
- pinned MCP config;
- skills, hooks and a PR template;
- a short workflow playbook.

Everything ships as small reviewable PRs. A human merges them. You don't.

### Where things stand (verify each on current `main`)

**Already done; build on it and don't redo it:**
- **JUN-22 (security)** and **JUN-45 (scalability and quality)** are merged.
- CI exists: `.github/workflows/ci.yml` runs build plus unit tests (skipping `ScalingTests`, `StoreKitEntitlementStoreTests` and `FeaturePrintTests/distanceMatchesVision()`), and lints changed files as warnings only. `docs/ci.md` documents the local equivalents.
- `.swiftformat` and `.swiftlint.yml` exist.
- `SWIFT_STRICT_CONCURRENCY = complete`, with Swift 5 language mode.

**Draft context files:**
- `docs/audit/drafts/ARCHITECTURE.md` is **tracked on `main`**. JUN-45 updated it with a Names table, `GroupingCache` and the schema-index lesson. Parts of it are still stale. For example, it says the external-change path always settles items as `gone`, and that place names "need disclosure", but S-2 now sends approximate locations.
- `docs/audit/drafts/CLAUDE.md` exists **only as an untracked local file** in the owner's working copy. It was never committed. Use it as input.
- The audit report and the three fix prompts under `docs/audit/` (`prompts/`) are also untracked local files.

**Missing:**
- a root `CLAUDE.md` / `AGENTS.md` / `ARCHITECTURE.md`;
- a `Makefile`;
- anything in `.claude/` except an empty `worktrees/`;
- a PR template.

`.mcp.json` runs `npx -y xcodebuildmcp@latest` (unpinned). `.gitignore` doesn't cover `.claude/` local files.

**Code changes since the audit that the docs must reflect:**
- `AdminController` and `FeedTypes.swift` (the hoisted enums);
- the `AssetCatalog` and `Geocoding` seams;
- `DeletionOutcome.make`;
- `GroupingCache` and `FeatureIndex.generation`;
- `currentAccess()`, the limited-access rules, and `presentLimitedPicker()`;
- decisions bound to `cardID`;
- `BristleSchemaV1` / `BristleMigrationPlan`;
- `Logger.appSubsystem`.

## Pre-flight (do this before planning)

1. Run `git status`. The owner's working copy may have:
   - untracked `docs/audit/` files (the report, `prompts/`, and both `drafts/`);
   - a local, uncommitted edit to `photo-swiper.xcscheme` that drops `parallelizable = "NO"` on the UI test target.

   **Don't commit the scheme edit.** UI tests rely on running serially. Tell the owner about it.
2. Sync `main`. If the pull is blocked because untracked `docs/audit/drafts/ARCHITECTURE.md` would be overwritten:
   - move the untracked `docs/audit/` tree to `docs/audit-local/`, pull, then move the untracked files back where they don't collide;
   - **the tracked ARCHITECTURE draft from `main` wins;**
   - keep the local `CLAUDE.md` draft, the report and the prompts.

   **Never delete the owner's untracked files.** Leave anything you're unsure about in `docs/audit-local/` and say so.
3. Run the CI-equivalent unit test command from `docs/ci.md` once on `main`, so you know the baseline is green. If it isn't green, stop and report.

## Ground rules

1. **Plan first.** Start in plan mode. Show the owner the PR list below with any changes you'd make, the exact files each PR adds, and anything you think is unnecessary. **Wait for approval** before writing.
2. **No app code changes.** Doing this right touches no Swift in `photo-swiper/`. If you find a doc that can only be made true by changing code, list it; don't change it. The exception is a code comment that is factually wrong and that a doc you're writing contradicts.
3. **Every claim in a doc must be checked against the code** at the commit you're on. Use symbol names, not line numbers. Prefer saying less over saying something that will go stale: commands, rules and boundaries belong in the docs, and descriptions of how a function works belong in code comments.
4. **Keep the instruction files short.** Root `CLAUDE.md` is at most about 120 lines, each nested `CLAUDE.md` at most about 25, and `ARCHITECTURE.md` at most about 200. Agents load them on every session, so every line has to earn its place.
5. **Check how tools are configured against current docs, not memory.** Claude Code's settings, hooks, skills, subagents and `@` imports, and XcodeBuildMCP's options, all change. Read the current documentation, follow it, and cite the page in the PR description. If a feature described here doesn't exist or works differently, adapt it and say so.
6. **Secrets and personal state stay out of git.** `.claude/settings.local.json`, `.claude/worktrees/`, and any hook state files are ignored. The project `.claude/settings.json` is committed and holds nothing personal.
7. **Git and Linear:**
   - One branch and one PR per group below, named `jun-23-<slug>`.
   - Commit messages: `chore(agents): … [JUN-23]`.
   - Work sequentially; stack on the previous branch if it isn't merged, and say so.
   - Open PRs with `gh` and **don't merge**. Each PR description has "What / Why / How verified / Risk".
   - Comment each PR link on JUN-23.
   - **Don't change issue statuses or create issues**, and don't touch JUN-5, unless the owner says so.
8. **Stop and ask** if any of these happen:
   - a decision you need is blank and has no default;
   - the baseline tests aren't green;
   - a hook or CI change would block normal work in a way the owner hasn't approved.

## Work, in order

### PR 1 — Context files at the root (A-1)

1. **`ARCHITECTURE.md`** at the root, made from `docs/audit/drafts/ARCHITECTURE.md` with `git mv`. **Refresh it against current `main`.**
   - Keep the Names table, layers, data flow, persistence, build variants and the short decisions (ADRs).
   - Update the layer map for `AdminController`, `FeedTypes`, the `AssetCatalog` / `Geocoding` seams and `GroupingCache`.
   - Fix the data-flow steps for limited access: items are settled as `gone` only under full access.
   - Fix approximate-location place names, and decisions bound to the card ID.
   - Keep the hard-won lessons, for example "a version that only adds `#Index` aborts at launch".
   - Add a **"Safety properties"** section listing the invariants any change must preserve, each with the test that guards it:
     - pile-only deletion, with the in-app alert before the iOS prompt;
     - decisions bound to the card ID (`CardIdentityTests`);
     - `FrontLoad` never moves the current card (`FrontLoadTests`);
     - limited access never settles items as `gone` (`LimitedAccessTests`);
     - write-through persistence;
     - the versioned schema (`SchemaVersioningTests`);
     - no new network use.
2. **`CLAUDE.md`** at the root, from the local untracked `docs/audit/drafts/CLAUDE.md`, rewritten for current `main`. Following D1, with the AGENTS.md option, `AGENTS.md` holds the content and `CLAUDE.md` imports it. It contains:
   - one paragraph saying what the app is, and "read `ARCHITECTURE.md` before structural work";
   - **commands** (`make …` once PR 2 lands; write them now and keep this PR stacked under PR 2, or put the raw `xcodebuild` lines in now and switch in PR 2);
   - mock launch arguments;
   - the **rules**: the safety properties in one line each with a pointer to `ARCHITECTURE.md`, write-through persistence, schema changes through `BristleSchema.swift`, `#if DEBUG` boundaries, logging privacy, layering (views → `FeedViewModel` → services through protocols), keeping ranking pure, Swift Testing for unit tests, and lint/format on touched files only;
   - **the human-review list**: deletion and pile logic; anything that changes which card or items a decision applies to; permissions and usage strings; `@Model` and schema changes; StoreKit and entitlements; `DevMode` gating; any new network use; privacy copy;
   - **Git conventions**: commit and PR title format `feat|bug|chore|perf(scope): summary [JUN-NN]`, one branch per issue, and update `ARCHITECTURE.md` in the same PR as any structural change;
   - **Don'ts**: `photo-swiper-context/`, the permanent IDs from the Names table, Linear status changes, and the shared scheme's `parallelizable` setting.
3. **Nested `CLAUDE.md` files, only where the local rules really differ.** Each is at most about 25 lines:
   - `photo-swiper/photo-swiper/Services/Persistence/`: how to add a schema version and the `#Index` lesson, write-through, and old JSON must still decode.
   - `photo-swiper/photo-swiper/Services/PhotoKit/`: this is the only place that deletes, so changes here need human review; limited-access semantics; no new network calls.
   - `photo-swiper/photo-swiperTests/`: Swift Testing conventions, mocks over PhotoKit, the injected `now`, `FeedViewModel+TestSwipes`, what CI skips and why, and "scaling tests are local only".

   Add a nested file for another directory only if you find a real local rule. Say why in the PR.
4. **Following D3:** commit `docs/audit/JUN-5-audit-report.md` and `docs/audit/prompts/*.md`. Add a short `docs/audit/README.md` saying the report is a point-in-time snapshot from 2026-11-08 and the prompts are historical, so agents don't treat them as current. Remove `docs/audit/drafts/` once both files have moved to the root.

### PR 2 — The command-line feedback loop (A-2)

1. **`scripts/sim-destination.sh`** prints a `platform=iOS Simulator,id=<UDID>` destination using the same "first available iPhone" logic as CI. `DEST` overrides it.
2. **A root `Makefile`** with a short `help` target that lists the others. The skip list exists in one place, a variable shared by the targets that need it:

   | Target | What it does |
   |---|---|
   | `build` | Incremental build, quiet output, non-zero on failure |
   | `test-unit` | Unit tests exactly as CI runs them, with the same three skips |
   | `test-all-unit` | Unit tests with no skips (needs a real Mac) |
   | `test-ui` | UI tests, with `-parallel-testing-enabled NO` |
   | `test-scaling` | Only `ScalingTests` |
   | `lint` | SwiftFormat lint plus SwiftLint on Swift files changed against `origin/main` |
   | `lint-all` | Both tools on the whole tree; informational |
   | `format` | SwiftFormat on changed files only |
   | `analyze` | `swiftlint analyze` with a fresh build log |
   | `verify` | `lint build test-unit`. **What an agent must run before saying "done".** |

   `test-ui` must stay off the default path because it's slow. The output is quiet but keeps failures and the "N passed / M failed" summary.
3. **Following D4:** switch `ci.yml` to the `make` targets (`make build`, `make test-unit`, `make lint` with `DEST` from the existing step) without changing what CI checks. The PR's own CI run is the proof. Update `docs/ci.md` to lead with the `make` commands.
4. **Verify:** run every target locally and paste the summary lines into the PR. Run `make verify` from a clean clone (`git worktree add`) to prove there are no hidden local dependencies, apart from `brew install swiftlint swiftformat jq`, which the `help` target mentions.

### PR 3 — MCP config and project settings (A-4)

1. **`.mcp.json`:** pin XcodeBuildMCP to an exact version (find the current one with `npm view xcodebuildmcp version`) and drop `@latest`. Start it once to confirm it works. Then check that it can build, run the unit tests and launch the app on a simulator with `-mockLibrary YES`. In `docs/agent-workflow.md` (PR 6), note which of its tools to use for what, and how to bump the pin.
2. **Inventory and recommend, without installing.** In the PR description, list the MCP servers available in the owner's environment that are relevant here: Linear and GitHub (or the `gh` CLI), plus any Apple-docs lookup. Say what each is for and whether it belongs in project config or account config. Linear is already connected at the account level, so don't add it to `.mcp.json`. **Don't add servers the owner hasn't approved.**
3. **`.claude/settings.json`, committed:**
   - **Allow:** `make` targets, `xcodebuild`, `xcrun simctl`, read-only `git` commands, `gh pr create|view|list|checks`, `swiftformat`, `swiftlint`.
   - **Deny:** `git push --force*`, `git reset --hard*`, `rm -rf` outside `DerivedData`/`build`, and editing `.git/`.
   - Use the current settings schema from the docs.
4. **`.gitignore`:** add `.claude/settings.local.json`, `.claude/worktrees/` and any hook state paths from PR 4.

### PR 4 — Hooks (A-3 + the post-edit loop)

Write each hook as a small, commented script in `scripts/hooks/`, wired in `.claude/settings.json`. Hooks must be **fast, idempotent, and safe when a tool is missing**: if `swiftformat` isn't installed, print a one-line hint and exit 0.

1. **`format-edited.sh` (`PostToolUse` on `Edit|Write`):** runs `swiftformat` on the single `.swift` file that was just edited, read from the hook's JSON input. Does nothing for other files.
2. **`guard-sensitive-paths.sh` (`PreToolUse` on `Edit|Write`):**
   - **Sensitive paths:** anything under `Services/PhotoKit/` and `Services/Persistence/`; `PendingPileView.swift`; `FeedViewModel.swift`; `CardStackView.swift`; `SwipeDeck.swift`; `FrontLoad.swift`; `PlaceNamer.swift`; `ProgressModels.swift`; `AssetFeatureRecord.swift`; `BristleSchema.swift`; any `*Entitlement*.swift`; `DevMode.swift`; `Info.plist`; `project.pbxproj`.
   - **The first edit to one of these in a session is blocked once,** with a message telling the agent to load the `privacy-destructive-guard` skill and add "Needs human review" to the PR. Later edits in the same session pass. Remember the acknowledgement in an ignored state file keyed by the hook's session ID.
   - Never block anything else.
3. **`build-on-stop.sh` (`Stop`, following D2):** if any `.swift` file differs from `HEAD` (staged or not), run `make build`. On failure, feed the last error lines back so the agent keeps working. Give up after a time limit rather than hanging. If no Swift changed, exit immediately.
4. **Verify each hook:** trigger it once in a real session (a no-op edit on a scratch branch) and paste what happened into the PR. Document how to turn each hook off temporarily.

### PR 5 — Skills and a reviewer subagent

Put the skills under `.claude/skills/<name>/SKILL.md`, following the current skill format: frontmatter `name` and a `description` that says *when* to use it, then concise steps. Each one points to `CLAUDE.md` and `ARCHITECTURE.md` instead of repeating them.

1. **`new-feature`**: use at the start of any feature or bug fix.
   1. Read `CLAUDE.md`, `ARCHITECTURE.md` and the Linear issue.
   2. Plan in plan mode: files, the seams to use, tests to add, and whether any sensitive path is touched.
   3. Write failing Swift Testing tests against the mocks.
   4. Implement until `make verify` passes.
   5. Update `ARCHITECTURE.md` in the same change if a boundary or data flow moved.
   6. Finish with `pre-pr`.
2. **`pre-pr`**: use before opening any PR.
   1. Run `make verify`, plus `make test-ui` if views or `FeedViewModel` changed.
   2. Check the diff against `main` for:
      - a new `print`;
      - `.public` logging outside `#if DEBUG`;
      - mocks escaping `#if DEBUG`;
      - new network or `CLGeocoder` use;
      - `@Model` changes without a schema version;
      - new `@unchecked Sendable` or `nonisolated(unsafe)` without a justification comment;
      - sensitive paths touched without "Needs human review";
      - a structural change without an `ARCHITECTURE.md` update.
   3. Draft the PR body from the template.
3. **`privacy-destructive-guard`**: loaded when the hook says so, or whenever deletion, permissions, persistence or data leaving the device is involved. It's a checklist of the safety properties, each with its guarding test, plus "how to prove you didn't weaken it". It ends by adding the "Needs human review" line with a one-sentence risk statement.
4. **`linear-to-pr`**: use when the owner says "take JUN-NN".
   1. Fetch the issue.
   2. Branch `jun-NN-<slug>` from the latest `main`.
   3. Run `new-feature`, then `pre-pr`.
   4. `gh pr create` with the title format.
   5. Comment the PR link on the issue.

   It never changes the issue's status, assignee or labels, and never merges.
5. **A `reviewer` subagent** (`.claude/agents/reviewer.md`, current subagent format). It's read-only and has tools for reading, search and running tests. It reviews a branch against `main` with fresh context, focusing on the safety properties and test coverage. It returns findings ranked by severity, with file and symbol references. `pre-pr` invokes it for any PR that touches a sensitive path.
6. **Verify:** invoke each skill once on a trivial scratch task (for example a comment-only change on a throwaway branch). Confirm each is discovered and does what it says. Delete the scratch branch and note the results in the PR.

### PR 6 — Workflow playbook, PR template and drift guard

1. **`docs/agent-workflow.md`**, at most about 120 lines, linked from `CLAUDE.md`:
   - **Plan mode vs direct edits.** Plan mode for anything crossing layers, anything on a sensitive path, `FeedViewModel`, the schema, or more than about 3 files. Direct edits for copy, styling, the DesignSystem, a single pure function with its tests, and docs.
   - **Scoping tasks.** One issue, one branch, one PR, under about 400 changed lines. Name the files and the seam. Tests first. Use the JUN-22, JUN-45 and JUN-23 prompts in `docs/audit/prompts/` as the template for big multi-PR efforts: owner decisions up front, a "what changed since" section, stop conditions.
   - **When a human must review:** the human-review list from `CLAUDE.md`.
   - **Keeping docs current:** the rule, the PR template checkbox, the CI drift warning (below), and a review of `CLAUDE.md` and `ARCHITECTURE.md` at each milestone that deletes rules that no longer apply.
   - **Tools:** which skill, hook and MCP to use when, how to turn hooks off, and how to bump the XcodeBuildMCP pin.
   - **Worktrees:** how to run parallel agents in git worktrees and clean them up afterwards (`git worktree prune`).
2. **`.github/pull_request_template.md`** with:
   - What / Why / How tested (`make verify` output; UI tests if relevant) / Risk;
   - a "Needs human review" checkbox with the list;
   - an "ARCHITECTURE.md updated, or not needed" checkbox;
   - a Linear issue line.
3. **The drift guard** (CI, **warning only**, in the lint job). If a PR adds, removes or renames Swift files under `Services/`, `ViewModels/` or `Models/`, or changes `BristleSchema.swift`, and doesn't touch `ARCHITECTURE.md`, post a warning annotation. Keep it to a few lines of shell inside `ci.yml`, or a `scripts/` helper.

## When you're done

Reply to the owner with:

1. **A table of the PRs:** each PR's link, files added or changed, and how it was verified.
2. **The setup at a glance:** files, `make` targets, hooks (and how to turn them off), skills, the subagent, MCP servers, and permissions.
3. **A suggested first real task to prove the loop end to end**, for example a small Low item from the audit run through `linear-to-pr`, and what the owner should watch for.
4. **Anything you couldn't make work as described,** and what you did instead.
5. A one-line reminder about the uncommitted local scheme change, if it's still there.
