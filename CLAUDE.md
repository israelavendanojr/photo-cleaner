# CLAUDE.md — Bristle (photo-cleaner)

Bristle is a private, on-device SwiftUI photo-cleaner for iOS 18+ (SwiftData, PhotoKit, no third-party dependencies). You swipe to keep or pile photos, and only the pile screen deletes. **Read `ARCHITECTURE.md` before structural work.** This file holds rules and commands only; `.claude/rules/` adds rules for persistence, PhotoKit and the unit tests, loaded when you touch those files.

## Commands

```sh
make verify         # lint + build + unit tests, as CI runs them. Run it before saying a task is done.
make build          # incremental build (app + tests); errors only, full log in build/logs/build.log
make test-unit      # unit tests with CI's skips
make test-ui        # UI tests, serially; slow (~15 min). Run when views or FeedViewModel change
make format         # SwiftFormat on the files you changed
make                # every target
```

- Run `xcodebuild` and the build and test targets **outside the Bash sandbox**. Inside it, codesigning silently doesn't run and tests fail to launch.
- The simulator is the first available iPhone (`scripts/sim-destination.sh`). Override with `DEST='platform=iOS Simulator,name=iPhone 16'`.
- `docs/agent-workflow.md` covers skills, hooks (and turning them off), worktrees and when to plan. `docs/ci.md` covers CI and the raw `xcodebuild` forms. XcodeBuildMCP (`.mcp.json`) can also build, launch and screenshot.

**Mock launch arguments** (Debug only; the full list is on `launch()` in `photo_swiperApp.swift`): `-mockLibrary YES`, `-startAt similar|batch|duplicates|video|pending|outOfSwipes|caughtUp|onboarding`, `-resetProgress YES`, `-resetOnboarding YES`, `-unlocked YES|NO`, `-mockProgress YES`, `-swipesLeft N`, `-refillSoon YES`.

## Rules

Safety properties. Each is spelled out, with the test that guards it, in `ARCHITECTURE.md` → Safety properties:

- **Only the pile deletes.** `PHAssetChangeRequest.deleteAssets` stays in `PhotoKitLibrary.delete`, reached only from `PendingPileView` after its in-app alert. A swipe only adds to the pile.
- **A decision applies to the card the user acted on.** Pass `cardID` through. Never re-read `currentCard` after anything that can reorder the deck.
- **`FrontLoad` never moves the current card.**
- **Limited access never settles items as `gone`.** Check `currentAccess() == .full` first.
- **Persistence is write-through.** Every mutating `ProgressStoring` call is durable when it returns.
- **Schema changes go through `BristleSchema.swift`.** Follow its V2 steps. New Codable fields on saved JSON (`LibraryItem`, `Session`, `AssetFeatures`) are optional, so old data still decodes.
- **No new network use.** No `URLSession`, SDKs or analytics. Place names send only an approximate location (`PlaceNamer`).

Code:

- **Mocks and debug-only code stay inside `#if DEBUG`.** Release must never read launch arguments or unlock for free.
- **Logging:** `Logger.app(category:)`. Never log identifiers, place names or file names as `.public` outside `#if DEBUG`. No `print`.
- **Layering:** views → `FeedViewModel` intents → services through protocols. Views don't touch PhotoKit or SwiftData. Collaborators (`SwipeGate`, `OnboardingFlow`, `ReminderController`, `FollowUpCoordinator`, `AdminController`) don't call each other. Don't widen view-model state to settable; add a narrow intent.
- **Ranking and grouping stay pure** (`Services/Ranking`, `Services/Analysis`): no PhotoKit, ties broken by ID, tested with made-up features.
- **Tests:** Swift Testing (`@Test`, `#expect`) for unit tests, against mocks and fakes; XCTest only for UI tests. See `.claude/rules/unit-tests.md`.
- **Lint and format only the files you touch** (`make lint`, `make format`). Don't reformat files you aren't otherwise changing.
- Doc comments explain *why*, in plain sentences. Update them when behavior changes.

## Needs human review

Say "Needs human review" in the PR, with one sentence of risk, when a change touches:

- deletion or pile logic;
- anything that changes which card or items a decision applies to;
- permission requests or usage strings (`Info.plist`);
- `@Model` types or the schema (`ProgressModels.swift`, `AssetFeatureRecord.swift`, `BristleSchema.swift`);
- StoreKit or entitlements;
- `DevMode` gating;
- any new network use;
- privacy copy (Settings, onboarding, usage strings).

## Git

- Commit and PR titles: `feat|bug|chore|perf(scope): summary [JUN-NN]`. One branch and one PR per Linear issue, branch `jun-NN-<slug>`.
- Update `ARCHITECTURE.md` in the same PR as any change to module boundaries, data flow or a safety property.
- Open PRs with `gh pr create`. Never merge or force-push.

## Don't

- Don't edit `photo-swiper-context/`. It's reference material, and gitignored.
- Don't change the permanent IDs in `ARCHITECTURE.md` → Names: the bundle ID `com.israelavendanojr.photo-swiper` and the product ID `com.israelavendanojr.photo-swiper.unlock`.
- Don't change Linear issue statuses, assignees or labels, or create issues, without asking.
- Don't change `parallelizable = "NO"` on the UI test target in the shared scheme. UI tests must run serially.
- Don't treat `docs/audit/` as current. It's a dated snapshot.
- Don't put docs or other non-code files in `photo-swiper/photo-swiper*/`. They're Xcode synchronized folders, so every file there ships in the app or test bundle (two `CLAUDE.md` files there even break the build). Agent rules go in `.claude/rules/`.
