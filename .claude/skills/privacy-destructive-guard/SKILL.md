---
name: privacy-destructive-guard
description: Load when the guard-sensitive-paths hook says so, or whenever a change touches deletion or the pile, which card a decision applies to, photo-library permissions or limited access, persistence or the schema, purchases, Developer mode, or anything that could send data off the device. A checklist of the app's safety properties and how to prove each still holds.
---

# Privacy and destructive-change guard

The properties are defined in `ARCHITECTURE.md` → Safety properties. For each one your change could affect, say how you showed it still holds. "I read the code" isn't proof; a passing test or a grep is.

| Property | Prove it with |
|---|---|
| Pile-only deletion: a swipe never deletes; `deleteAssets` only in `PhotoKitLibrary.delete`, reached only from `PendingPileView` after its alert | `git grep -n deleteAssets` shows one call site; `git grep -l deleteNow -- '*.swift'` shows only `FeedViewModel` (its definition), `PendingPileView` and tests; the alert still precedes `vm.deleteNow` |
| Decisions bind to the card the user acted on | `CardIdentityTests` pass; every new decision path takes a `cardID` and checks it against the current card |
| `FrontLoad` never moves the current card | `FrontLoadTests` pass |
| Limited access never settles items as `gone` | `LimitedAccessTests` pass; any new `settle(…, as: .gone)` is behind `currentAccess() == .full` |
| Write-through persistence | `ProgressWritesTests` and `ProgressStoreTests` pass; no new deferred or batched save of decisions |
| Versioned schema | `SchemaVersioningTests` pass; a model change follows `BristleSchema.swift`'s V2 steps; new saved-JSON fields are optional |
| No new network use; place names stay approximate | `PlaceNamerTests` pass; `git diff origin/main...HEAD` adds no `URLSession`, `import Network`, new `CLGeocoder` or `isNetworkAccessAllowed = true` |
| Debug-only stays debug-only | New mocks, launch arguments and unlock paths are inside `#if DEBUG`; `DevModeTests` pass |
| Permission and privacy copy still match behavior | `Info.plist` usage strings and Settings' privacy text describe what the code now does |

Run `make verify` (it runs all of the suites above). For UI-visible delete or permission flows, also run `make test-ui`.

**Finish** by adding this to the PR body, with one sentence of risk:

> **Needs human review:** <area>. Risk: <what could go wrong for the user if this is wrong>.
