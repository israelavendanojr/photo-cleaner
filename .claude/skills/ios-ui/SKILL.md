---
name: ios-ui
description: Use before building or changing any SwiftUI view in this repo (anything under Views/ or DesignSystem/, new screens such as onboarding, copy or styling changes). Points to DESIGN.md, the DS tokens and components to use instead of literals, the HIG patterns this app follows, and the accessibility, light/dark and device-size checks to run.
argument-hint: "[screen or JUN-NN]"
---

# SwiftUI work in Bristle

`DESIGN.md` is the design system and `CLAUDE.md` holds the rules. Don't restate them; follow them.

1. **Read first.** Read `DESIGN.md`, then the views you'll touch and their neighbors. Before writing a new view, look in `photo-swiper/photo-swiper/DesignSystem/Components/` and DESIGN.md → Components. Most needs are already covered (pills, chips, circle buttons, `UpsellLayout`, `onboardingLayout`).
2. **Tokens, never literals.** Use `DS.Palette`, `DS.Spacing`, `DS.Radius` (with `.continuous`), `DS.Motion`, `.dsSerif(_:relativeTo:)`, `cardShadow()`/`softShadow()`, `Haptics.*` and `Format.*`. If a value you need doesn't exist, add the token to `DesignSystem.swift` and a line to `DESIGN.md` in the same change. Don't hardcode it once. Brick is only for deletion, amounts to clear and celebrations. Use at most one `.pill(.brick)` per screen.
3. **HIG, as this app applies it.**
   - Use system alerts, confirmation dialogs and sheets, never custom alert UI.
   - Destructive actions confirm. Only the pile deletes; a swipe only adds to it (CLAUDE.md → Rules).
   - Use SF Symbols with the action vocabulary in DESIGN.md → Iconography.
   - Keep controls in the thumb zone. One primary action per screen.
   - Ask for permissions only after a primer screen explains why (`PhotoAccessPrimerView`, `NotificationsPrimerView`).
4. **Accessibility, every time.**
   - Text scales: text styles, or `dsSerif`/`@ScaledMetric`. Long content scrolls instead of clipping.
   - Tap targets are at least 44×44pt.
   - VoiceOver: label icon-only buttons, combine compound values, `.isHeader` on titles, hide decoration, announce async results.
   - Reduce Motion: every movement has a still or fade fallback.
   - Contrast: no essential small text in `secondary` or brick-on-tint (DESIGN.md → Accessibility).
   - Add `accessibilityIdentifier("screen.element")` for anything a UI test will tap.
5. **Previews.** Give each view a `#Preview` on mock data (`PreviewSamples`, `FeedViewModel.mock()`) and a second preview at `.dynamicTypeSize(.xxLarge)`. Put previews that use mocks inside `#if DEBUG`.
6. **Look at it.** Run the app on the mock library (`-mockLibrary YES -startAt <screen>`, list in CLAUDE.md) with XcodeBuildMCP or `make` plus `DEST=`:
   - on a small iPhone (SE or mini class) and a Pro Max;
   - in light and dark appearance (`xcrun simctl ui booted appearance dark`). Dark mode isn't designed yet; check that nothing becomes unreadable and that system chrome still makes sense;
   - at an accessibility text size (`xcrun simctl ui booted content_size accessibility-large`).
7. **Layering.** Views read `FeedViewModel` and call its intents. They never touch PhotoKit, SwiftData or a collaborator directly.
8. **Finish.** Run `ui-review` on your diff and fix its blockers. Then run `make verify`, and `make test-ui` alone since views changed. Then run `pre-pr`.
