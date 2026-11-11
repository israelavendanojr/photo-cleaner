---
name: ui-review
description: Use to review a SwiftUI diff, file or screen in this repo against DESIGN.md and Apple's HIG, for example before a PR that touches Views/ or DesignSystem/, or when asked whether a screen is on-brand or accessible. Read-only. Reports violations by severity with file:line and the fix, and doesn't edit.
argument-hint: "[branch, file, or screen]"
---

# UI review

Read `DESIGN.md` first. This review only reports. Don't edit files.

1. **Scope.** By default, review the Swift changes under `Views/` and `DesignSystem/`: `git diff origin/main...HEAD -- 'photo-swiper/photo-swiper/Views' 'photo-swiper/photo-swiper/DesignSystem'` plus any uncommitted changes. If given a file or screen, read it whole. If given a screenshot, review what's visible.
2. **Mechanical checks.** Check added lines only (`+` lines). Each hit is a finding unless the rule's exception applies:
   - `Color(hex` outside `DesignSystem.swift`; `.red`, `.gray`, `.blue` and other system colors. `.white`/`.black` are fine only over media or on an ink/brick fill.
   - `.padding(` or `spacing:` with a nonzero number literal instead of `DS.Spacing` (`0` is fine).
   - `cornerRadius:` with a literal, or a `RoundedRectangle` without `style: .continuous`.
   - `.font(.system(size:` that doesn't go through `@ScaledMetric`; a serif that doesn't use `dsSerif`.
   - `.shadow(` instead of `cardShadow()`/`softShadow()`.
   - `withAnimation(.ease…`, `.spring(`, `.linear` or `.animation(.ease…` instead of `DS.Motion`.
   - `.sensoryFeedback` or `UI…FeedbackGenerator` outside `Haptics.swift`.
   - Sizes, dates or counts formatted inline instead of with `Format`.
   - A `Button` or `Image` with only a symbol and no `accessibilityLabel` (or not hidden, if it's decorative).
   - A `.frame(width:height:)` under 44 on something tappable without a larger `contentShape`.
3. **Judgment checks.**
   - Brick only means deletion, amounts or celebration, with at most one `.pill(.brick)` per screen. Brick on a non-delete action is a **blocker**.
   - The right existing component is used (DESIGN.md → Components). A new component isn't a near-copy of one that exists.
   - Movement has a Reduce Motion fallback.
   - The screen scrolls instead of clipping at XXL and accessibility sizes, and has an XXL `#Preview`.
   - Titles have `.isHeader`, compound values read as one sentence, and async results are announced.
   - HIG: system alerts and dialogs, one primary action, a confirmation before anything destructive, a primer before a permission prompt.
   - Copy is in sentence case, plain and honest (DESIGN.md → Principles). It has no exclamation marks and no urgency tricks.
   - The view doesn't reach past `FeedViewModel` (CLAUDE.md → Layering).
4. **Report.** List findings in three groups:
   - **Blocker:** accessibility failures, or a misuse of brick or of destructive styling.
   - **Should fix:** token, component or motion violations.
   - **Nit.**

   Give each finding `file:line`, what's wrong, the DESIGN.md section, and the one-line fix. Leave out items already listed in DESIGN.md → Inconsistencies / TODO, unless the diff adds more of them. If nothing is found, say so.
