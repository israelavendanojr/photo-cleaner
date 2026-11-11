---
name: new-feature
description: Use at the start of any feature or bug fix in this repo, before writing code. Plans the change in plan mode, writes failing Swift Testing tests against the mocks, implements until `make verify` passes, and keeps ARCHITECTURE.md current.
argument-hint: "[JUN-NN or short description]"
---

# New feature or bug fix

Rules and commands are in `CLAUDE.md`; layers, data flow and safety properties are in `ARCHITECTURE.md`. Don't restate them; follow them.

1. **Read.** `CLAUDE.md`, `ARCHITECTURE.md`, and the Linear issue if there is one (Linear MCP `get_issue`, plus `list_comments`). Read the code you'll touch and its doc comments.
2. **Plan in plan mode.** Name:
   - the files you'll change and the layer each is in;
   - the seam you'll use (a protocol in `Services/` with a mock in `Services/Mock/`, or a fake in the tests), never a direct PhotoKit or SwiftData call from a view;
   - the tests you'll add, and which existing suite guards the area;
   - whether you touch a sensitive path (the `guard-sensitive-paths` hook list). If so, load `privacy-destructive-guard` now.
   Keep the change under ~400 lines; split it otherwise. Wait for approval.
3. **Tests first.** Write Swift Testing tests that fail for the right reason, against `FakeLibrary`, `MockFeedBuilder`, `InMemoryProgressStore` / `SwiftDataProgressStore.inMemory()` and an injected `now`. Run `make test-unit` and see them fail.
4. **Implement** until `make verify` passes. Fix warnings in code you touched.
5. **Docs.** If a module boundary, data flow or safety property moved, update `ARCHITECTURE.md` in the same change. Update doc comments whose *why* changed.
6. **Finish with `pre-pr`.**
