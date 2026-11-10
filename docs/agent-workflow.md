# Working with agents in this repo

How to give an agent (Claude Code, or anything that reads `CLAUDE.md`) work here, and what the repo does to keep it safe. Rules and commands live in `CLAUDE.md`; this is the playbook around them.

## Plan mode or direct edits

**Plan mode first** for anything that:

- crosses layers (view + view model + service);
- touches a sensitive path: deletion, the pile, decisions, permissions, persistence or the schema, purchases, Developer mode, place names (the list is in `scripts/hooks/guard-sensitive-paths.sh`);
- changes `FeedViewModel`;
- spans more than about 3 files.

**Direct edits** are fine for copy, styling, the DesignSystem, a single pure function with its tests, and docs.

## Scoping a task

- One Linear issue → one branch (`jun-NN-<slug>`) → one PR, under about 400 changed lines. Split anything bigger.
- Name the files or module, and the seam: "add a protocol in `Services/`, a mock in `Services/Mock/`", or "fake `AssetCatalog` in the test".
- Ask for tests first, against the mocks, then the implementation.
- For a big multi-PR effort, write a prompt like the ones in `docs/audit/prompts/`: owner decisions up front with defaults, a "what changed since" section, the PR list, and stop conditions.

## When a human must review

The list is in `CLAUDE.md` → Needs human review. The PR template has the checkbox, and the `guard-sensitive-paths` hook makes the agent acknowledge it the first time it edits one of those files in a session.

## Keeping the docs current

- Structural changes update `ARCHITECTURE.md` in the same PR. The PR template asks, and CI's lint job warns when files under `Services/`, `ViewModels/` or `Models/` are added, removed or renamed, or `BristleSchema.swift` changes, without an `ARCHITECTURE.md` change (`scripts/check-architecture-drift.sh`; a warning, never a failure).
- `CLAUDE.md` and `.claude/rules/` hold rules and commands only. How a function works belongs in its doc comment.
- At each milestone (Beta, 1.0), reread `CLAUDE.md`, `.claude/rules/` and `ARCHITECTURE.md`, and delete rules that no longer apply.

## Tools

| Use | When |
|---|---|
| `make verify` | Before saying any task is done. CI runs the same targets |
| `make test-ui` | When views or `FeedViewModel` changed. Run it alone |
| Skill `new-feature` | Start of a feature or fix |
| Skill `pre-pr` | Before opening a PR |
| Skill `privacy-destructive-guard` | When the guard hook says so, or the change touches a safety property |
| `/linear-to-pr JUN-NN` | "Take JUN-NN" end to end. Only you can start it; the model won't on its own |
| Subagent `reviewer` | Fresh-context review of a branch; `pre-pr` calls it for sensitive changes |
| XcodeBuildMCP | Run the app and look at it. Defaults don't persist between server starts, so begin each session with `session_set_defaults` (`projectPath` = `photo-swiper/photo-swiper.xcodeproj`, `scheme` = `photo-swiper`, `simulatorName` = e.g. `iPhone 16 Pro`). Then `build_run_sim` with `launchArgs: ["-mockLibrary", "YES", "-startAt", "similar"]`, `screenshot`, `snapshot_ui`. `test_sim` works too (with `-only-testing:` in `extraArgs`), but `make` is the reference. It builds into its own DerivedData |
| Linear MCP (account connector) | Read issues and comment PR links. Never change status |

### Hooks (`.claude/settings.json`)

| Hook | What it does | Turn it off for a session |
|---|---|---|
| `format-edited.sh` (after Edit/Write) | SwiftFormat on the edited `.swift` file, if it was formatted at HEAD | `BRISTLE_FORMAT_OFF=1` |
| `guard-sensitive-paths.sh` (before Edit/Write) | Blocks the first edit to a sensitive path once per session | `BRISTLE_GUARD_OFF=1` |
| `build-on-stop.sh` (end of turn) | `make build` if Swift changed since the last green build; sends errors back. Gives up after 240 s (`BRISTLE_BUILD_TIMEOUT`) or 3 failures | `BRISTLE_BUILD_OFF=1` |

`BRISTLE_HOOKS_OFF=1` turns off all three. Set these in the shell before starting `claude`, or in `.claude/settings.local.json` under `"env"`. `"disableAllHooks": true` in `.claude/settings.local.json` turns off every hook, including your own. Hook state (guard acknowledgements, the last green build) is in `.claude/hook-state/`, which is gitignored and safe to delete.

### Permissions

`.claude/settings.json` allows the `make` targets, `xcodebuild`, `simctl`, the linters, read-only git and `gh pr create|view|list|checks`. It denies force pushes, `git reset --hard`, `rm -rf` (use `make clean`) and edits under `.git/`. Deny rules match the command text, so they're guard rails, not a sandbox. Put personal additions in `.claude/settings.local.json`. The shared allow rules apply only after you've trusted the folder once in an interactive `claude` session; until then headless runs (`claude -p`) still prompt or refuse. Deny rules apply right away.

### Bumping the XcodeBuildMCP pin

`.mcp.json` pins `xcodebuildmcp@<version>`. To bump it, read the release notes, run `npm view xcodebuildmcp version`, change the version, restart Claude Code, and check that `build_run_sim` still launches the app on the mock library. Do it in its own `chore(agents)` PR. Never go back to `@latest`.

## Parallel agents in worktrees

```sh
git worktree add ../photo-cleaner-jun-NN -b jun-NN-<slug> origin/main
cd ../photo-cleaner-jun-NN && claude
```

- Each worktree builds into its own `build/DerivedData`, so builds don't collide.
- **Simulators do collide.** Two test runs on one simulator crash each other's test host. Give each other worktree its own device, e.g. `DEST='platform=iOS Simulator,name=iPhone 16 Pro Max' make test-unit` (the default is the first available iPhone). Run UI tests in one worktree at a time.
- When a branch is merged, run `git worktree remove ../photo-cleaner-jun-NN`, then `git worktree prune` to drop entries for folders that are already gone.
