# DESIGN.md — Bristle design system

This is how Bristle looks, moves and reads. It describes the code as it is. The tokens and components live in [`photo-swiper/photo-swiper/DesignSystem/`](photo-swiper/photo-swiper/DesignSystem/), under the `DS` namespace. **If this file and the code disagree, the code wins.** Fix this file in the same PR.

For UI work, load the `ios-ui` skill. To check a diff against this file, load `ui-review`. Both are in [`.claude/skills/`](.claude/skills/).

## Principles and tone

- **Warm and quiet.** The app is ink on creased paper, light or dark, with one accent. The photos are the color on screen, so the chrome stays out of their way.
- **Brick means "this goes away".** The accent marks deletion, amounts to clear and the celebration when space is freed, and nothing else. When something is brick, the user should read it as "this frees space".
- **Calm motion.** Springs settle with little bounce. Nothing loops for attention, and every flourish has a still fallback under Reduce Motion.
- **Serif for moments, system for work.** Newsreader (`dsSerif`) is for headlines and big numbers. SF in system text styles is for everything you read or tap.
- **Plain words.** Copy is in sentence case and short sentences, with no exclamation marks and no dark patterns. Say what happens: "They'll stay in Recently Deleted for 30 days."
- **Private by design.** Nothing on screen implies a cloud. Don't add account, sync or sharing affordances.

## Color

Defined in `DS.Palette` ([`DesignSystem.swift`](photo-swiper/photo-swiper/DesignSystem/DesignSystem.swift)). Every token has a light and a dark value behind one name, as a color set in `Assets.xcassets/Palette/`, and the app follows the system appearance. Views never name a hex value; a new color is a new color set and a line here.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#FAF7F2` | `#171412` | The background's color, under the paper texture. `LaunchBackground` matches it in both modes. |
| `card` | `#FFFDF9` | `#231F1C` | Raised surfaces: chips, neutral round buttons, the tab bar, plan cards. |
| `ink` | `#1F1B18` | `#F3EEE6` | Primary text and icons, `.pill(.ink)`, the selected tab, Keep. Also the usual `.tint`. |
| `onInk` | `#FFFFFF` | `#171412` | Text and icons on an `ink` fill. Ink turns pale in dark mode, so fixed white there would vanish. |
| `secondary` | `#5F5750` | `#A99F95` | Supporting text, captions, inactive tabs. |
| `brick` | `#B23F30` | `#E67862` | Delete, amounts to clear, celebrations, as text, icons and ticks. **Never anything else.** |
| `brickFill` | `#B23F30` | `#C24A3A` | A brick surface under white text: `.pill(.brick)`, Save, a delete mark. |
| `brickTint` | `#F5E4DF` | `#3B211C` | Background behind brick content: the Delete circle, brick chips, the bin. |
| `line` | `#DDD5C9` | `#352F2A` | Hairline rules and quiet borders. |
| `outline` | `#CFC6B9` | `#453D36` | The empty part of a tick track, and the ring of an outlined control. |
| `muted` | `#EEE8E0` | `#2C2723` | Placeholder fill behind images while they load. |
| `shadow` | `#4A382B` | `#000000` | Shadow color only, through `cardShadow()` and `softShadow()`. |

**Fixed white and black** are allowed in only two places: over photos and video (preview chrome, card captions, scrims, `Chip(.frosted)`), and white on `brickFill`. On an `ink` fill use `onInk`.

**The paper.** Every screen sits on `PaperBackground` (`.paperBackground()`): the `paper` color under the `Paper` image, a creased-paper texture with a light and a dark version. It fills the screen under the safe areas, keeps its proportions, and never moves. Don't put an opaque `paper` fill over it at screen level.

**Forced dark.** The full-screen previews ([`PhotoPreviewView`](photo-swiper/photo-swiper/Views/Preview/PhotoPreviewView.swift), [`VideoPreviewView`](photo-swiper/photo-swiper/Views/Preview/VideoPreviewView.swift)) and `Chip(.frosted)` force `.dark` on purpose, because they sit on media.

## Typography

**Serif:** `.dsSerif(size, relativeTo:weight:italic:)` sets Newsreader at a design size through `@ScaledMetric`, so it still scales with Dynamic Type. Newsreader is bundled (`Resources/Fonts/`, two variable fonts under the SIL Open Font License, whose text ships beside them) and listed in `UIAppFonts`; `DS.Serif` sets its weight and optical-size axes, and falls back to New York if it didn't load. Always pass the `relativeTo` text style the size stands in for. The sizes in use:

| Size | `relativeTo` | Weight | Where |
|---|---|---|---|
| 48 | `.largeTitle` | regular | Big numbers: pile total, a video card's file size, the dashboard's space cleared (brick) |
| 46 | `.largeTitle` | medium | Welcome headline |
| 40 | `.largeTitle` | medium | Onboarding page titles |
| 34 | `.largeTitle` | medium | Screen titles (Library, pile, Admin, `UpsellLayout`); regular on empty states ("Nothing cleared yet") |
| 28 | `.title2` | regular | `ToClearCounter` |
| 26 | `.title` | regular | Photo card date |
| 22 | `.title3` | regular, *italic* for group cards | Similar and duplicate card titles, the unlock offer's "One-time purchase." |
| 20 | `.title3` | regular | Video card date |
| 19 | `.headline` | medium | Navigation-bar title (Settings) |

**System:** everything else uses semantic text styles, never `.font(.system(size:))`:

- `.headline` for button labels (`PillButtonStyle`) and toolbar buttons
- `.body` / `.callout` for reading text; `.callout` for supporting sentences under a headline
- `.subheadline` for eyebrows, chips and tab labels (`.semibold` where it's a control)
- `.footnote` / `.caption` / `.caption2` for metadata, captions and badges

Numbers that change use `.monospacedDigit()` and `.contentTransition(.numericText(value:))`. Format every size, date, duration, count and percentage with `Format` ([`Formatting.swift`](photo-swiper/photo-swiper/DesignSystem/Formatting.swift)), never inline. That includes chart axis labels.

## Spacing and layout

`DS.Spacing`: `xxs` 4 · `xs` 8 · `s` 12 · `m` 16 · `l` 20 · `xl` 28 · `xxl` 40, plus `cardInset` 14, which is the card stack's inset from the screen edge.

- **Screen gutter:** `l` (20) horizontally on most screens. Onboarding uses `xl` (28) through `onboardingLayout`.
- **Stack spacing:** `xs` inside a group, `s`–`m` between rows, `l`–`xl` between sections.
- **Large text scrolls, it doesn't clip.** Put content in a `ScrollView` with `.scrollBounceBehavior(.basedOnSize)`, and pin the primary action below it. Two layouts already do this:
  - `onboardingLayout(footerOrder:footer:)` ([`OnboardingEntrance.swift`](photo-swiper/photo-swiper/Views/Onboarding/OnboardingEntrance.swift)) for onboarding pages;
  - `UpsellLayout` ([`UpsellLayout.swift`](photo-swiper/photo-swiper/DesignSystem/Components/UpsellLayout.swift)) for every unlock screen: an eyebrow, a serif headline, a supporting sentence, an optional `UpsellCard`, then the offer.
- Full-width buttons are `.frame(maxWidth: .infinity)`, which `PillButtonStyle` already applies. Side-by-side pills share an `HStack(spacing: DS.Spacing.s)`.

## Corner radius and elevation

`DS.Radius`: `card` 32 · `inner` 24 · `tile` 16 · `thumb` 12. Always use `RoundedRectangle(cornerRadius:style: .continuous)`. Pills, chips, toasts and tab bars are `Capsule()`, and round buttons are `Circle()`.

| Radius | For |
|---|---|
| `card` | Feed cards and anything clipped to them (`SwipeOverlay`) |
| `inner` | Panels inside a screen: `UpsellCard`, image areas inside a card |
| `tile` | Grid tiles and smaller grouped surfaces |
| `thumb` | Thumbnails |

**Elevation** has two levels. Each is a tight contact line under a short drop, so a surface reads as paper lying on paper; the values are in `DS.Shadow`, heavier in dark mode, where a soft shadow wouldn't show.

- `cardShadow()`: cards, photos and stamp discs.
- `softShadow()`: chips and `PillTabBar`. `softShadow(raised: true)` is a touch firmer, for a surface that's a choice.

Put the shadow on the background shape, not on the view that holds text, so the text doesn't get a halo (`UpsellCard` shows the pattern). The only material is `.ultraThinMaterial`, used for controls over media.

## Iconography

- SF Symbols only. Use `.medium` or `.semibold` weight to match the type next to the icon, and size icons with a text style or `@ScaledMetric`.
- Selected states use the `.fill` variant (`PillTabBar.Item.selectedSystemImage`).
- The action vocabulary is fixed. Don't use another symbol for these meanings:

  | Meaning | Symbol |
  |---|---|
  | Delete / pile | `trash` (`trash.fill` for the bin) |
  | Keep | `checkmark` |
  | Later | `arrow.up` |
  | Undo | `arrow.uturn.backward` |
  | Close | `xmark` |
  | Best pick | `star.fill` |
  | Trimmed | `scissors` |
  | Compressed / compression | `arrow.down.right.and.arrow.up.left` |

- Symbol effects: `.symbolEffect(.bounce, value:)` when a count or selection changes, and `.contentTransition(.symbolEffect(.replace))` for toggles such as play and pause.
- Decorative icons get `.accessibilityHidden(true)`. Icon-only buttons get an `accessibilityLabel`.

## Motion and haptics

**Animations** come from `DS.Motion`:

| Token | Use |
|---|---|
| `snapBack` | A dragged card returning to center |
| `flyOut` | A card leaving the stack: fast out, with a long soft tail |
| `calm` | General state changes: counters, stack promotion, undo, button press |
| `gentle` | Screen-level transitions, big reveals, onboarding entrances |
| `page` | Moving between onboarding pages |
| `tab` | The tab bar's selection capsule |
| `tickFill` | `BristleTicks` sweeping to a new value, tick by tick |
| `countUpDuration`, `countUpSteps` | The dashboard's space cleared counting up from zero, and its ticks filling from empty alongside: once per launch, in steps of `calm` changes, easing out |

**Reduce Motion:** read `@Environment(\.accessibilityReduceMotion)` and show the end state at once, or swap movement for a fade. Examples: `OnboardingEntrance`, `DealIn`, `SwipeableCard` (no nudges), `ConfettiView` (a fading note instead of confetti), `StackedPhotosIllustration`.

**Haptics** come from `Haptics` ([`Haptics.swift`](photo-swiper/photo-swiper/DesignSystem/Haptics.swift)), with one function per moment: `threshold`, `advance` (also a dashboard suggestion tapped), `accessGranted`, `delete`, `refused`, `confirm`, `unlocked`, `tabChange`, `refreshed` (pull to refresh finished). A new moment gets a new function there. Views don't create `UI*FeedbackGenerator`s or use `.sensoryFeedback` directly.

## Components

All of these are in [`DesignSystem/Components/`](photo-swiper/photo-swiper/DesignSystem/Components/), and each has a `#Preview`. Check this list before building something new.

| Component | Use when |
|---|---|
| `PillButtonStyle`, applied as `.buttonStyle(.pill(_:))` | Any full-width action. `.ink` is the primary action, `.brick` is reserved for the destructive or paid primary (Delete N, Unlock), `.outline` is secondary, `.ghost` is tertiary ("Not now"). One brick button per screen at most. |
| `CircleActionButton` | The feed's round action-bar buttons with a caption. `.destructive` for Delete, `.neutral` for Keep and Later. |
| `CircleIconButton` | The outlined 44pt icon button in top bars (Undo, Close). Requires `accessibilityLabel`. |
| `PressScaleStyle` | The press-down scale for custom icon buttons. It also dims the button when disabled. |
| `Chip` | Small rounded labels. `.brick` for counts tied to clearing (swipes left), `.plain` for neutral markers over imagery (Best pick, Keep) and the feed's focus ("Only large videos ×", with `trailingSystemImage: "xmark"`, which takes the text color), `.frosted` for text over video. |
| `PillTabBar` | The floating tab bar. Its selection animates with `DS.Motion.tab` and fires `Haptics.tabChange`. |
| `BristleTicks` | Any progress or proportion: upright 2pt strokes on a 5pt pitch (`DS.Ticks`), the filled part over an `outline` track, drawn in a `Canvas`. Ink by default, brick for amounts to clear. `showsTrack: false` for a bar that only compares sizes; `popsNew` lifts ticks as they fill. It fills tick by tick, from empty the first time it's seen (at once under Reduce Motion), scales its height with Dynamic Type, and reads its percentage to VoiceOver: give it a label where it's used. `BristleMark` is the glyph made from it, for the wordmark. |
| `ToClearCounter` | The brick serif running total, with a "+3.4 MB" chip that pops above it. Unlocked, it's the whole bin, edits included; with a free limit it's the deletes the limit counts. |
| `Toast` | A short note in an ink `Capsule()` with an optional underlined action, announced to VoiceOver, e.g. the feed's "Edit queued · saves ~335 MB · Undo". The caller decides how long it stays. |
| `UpsellLayout` / `UpsellCard` / `IncludedRow` | Every unlock surface (the wall and the sheets), so they read as one offer. |
| `ConfettiView` | The celebration after freeing space. It never takes touches, announces `message`, and falls back to a note under Reduce Motion. |
| `OpenSettingsButton` | Any link to the app's page in iOS Settings (permissions). |
| `SwipeStamp` (in `Views/Feed/`) | The Delete, Keep and Later wash over a card. It's also used in onboarding's demo. |
| `DashboardCard` | A dashboard panel: a header view, then content, on a `card` panel at `Radius.inner` with `softShadow()` on the shape. The hero and the library card use it. |
| `BinCard` | The pile on the dashboard: `trash` in brick on a `brickTint` circle (`DS.Bin.iconDiameter`, scaled), like the feed's Delete, then "Bin" and "N to clear · size" in brick. With a free limit, brick `BristleTicks` of the pile against it and "56.6 MB of 64 MB" ("Full at …" when full). Empty, it looks the same with zeros and an empty track. Wrap it in the link to the pile only when there's something in it: a disabled link would dim its text. One VoiceOver sentence. |

Formatting goes through `Format` (`size`, `signedSize`, `percent`, `signedPercent`, `weeklyChange`, `day`, `shortDay`, `range`, `duration`, `countdown`, `roughDays`, `spelled`, `count`). `size` uses `ByteCountFormatter` in decimal units from MB up, as Photos and Settings do ("1.2 GB", "0.1 MB"), and reads "0 MB" for nothing. `signedPercent` has one decimal ("+34.5%", "−25.0%"); `weeklyChange` reads "+1.2 GB (+34.5%) vs last week", or "+1.2 GB this week" when last week cleared nothing.

### The full-screen video, its trim strip and compression

`VideoPreviewView`, after Photos' video editor without its tool tabs or Cancel/Done. It's forced dark and sits on black, so fixed white and black are allowed here (see Color).

- **Top bar:** round frosted (`.ultraThinMaterial`) 44pt buttons, Close and volume on the left, the size and short date in the middle, and Compress (`arrow.down.right.and.arrow.up.left`) on the right. Compress turns brick once a level is set, like the strip once trimmed. Where it isn't offered (compression off, slow-motion, Cinematic) its slot stays empty, so nothing moves.
- **`CompressionPopup`**, a centred frosted card over the video (`.ultraThinMaterial`, dark, white text, `DS.Radius.card`, at most `DS.Popup.maxWidth` wide), in the style of the viewer's other controls. It's a deliberate custom popup rather than a system sheet: the video stays visible, live and holdable around it, with no scrim. "Compress" and a line on what it does, a round frosted close button (`FrostedIconButton`, `xmark`) beside them, then None / Light / Balanced / Max as rows on a lighter frost (white at 12%) at `DS.Radius.tile` (a `checkmark.circle.fill` on the choice, the level's caption under its name: "Original quality", "Looks the same", none, "Fine on a phone"), each with "380 MB → ~120 MB" after the trim, and Apply as a brick capsule like Save. A level that saves under 10% is at 40% opacity and reads "Already small". It scales in (fades with Reduce Motion); the close button, Apply, a tap on the video outside it, or VoiceOver's escape closes it. At large text its rows scroll inside the card. Choosing a level previews it: "Preview · Balanced" as a frosted `Chip` where the 2x pill goes, with a small white spinner while it encodes, and "Original" while the video is held.
- **Bottom bar:** one flat bar, as in Photos, with nothing around it: the play button on a frosted segment, a black hairline, then `TrimStrip` at the same height. Its outer corners are `DS.Trim.cornerRadius`. The play button sits above the strip, so the start handle's touch area never takes its taps.
- **`TrimStrip`** (`DS.Trim`): stills across the clip at `stripHeight` (scaled), a white `playheadWidth` playhead, and chevron handles of `handleWidth` outside the stills, each reaching a 44pt touch area outward. Untrimmed, there's no frame: white chevrons sit on the same frosted ground as the play button, so the bar reads as one piece. Once a handle moves, the frame (`frameWidth`) and handles turn brick (space to clear), and what's cut is dimmed with black. With no handles (short clips, slow-motion, Cinematic, trimmer off) it's a plain seek bar.
- **Edit summary**, above the panel once trimmed or compressed: "0:08 · 1.23 GB → 0:05 · ~752 MB" in footnote semibold, "saves ~476 MB" (trim and compression together) in subheadline bold under it, and while the edit differs from what's saved, Reset (frosted capsule) and Save (brick capsule), both 44pt tall.
- **Leaving** with an unsaved trim or level uses a system `.confirmationDialog`, "Save changes?": Save changes, Discard (destructive), Keep editing (cancel).

### The bin's edits and clearing

- **Edits section** in `PendingPileView`, under the photo grid: one `EditRow` per video on `card` at `DS.Radius.tile`, with the thumbnail, then the marks ("Trimmed", "Compressed · Balanced", or both) as `caption` semibold ink labels with their symbols, the change ("1:42 → 0:12 · 380 MB → ~45 MB") in subheadline semibold, and "saves ~X" in brick footnote. Swiping a row left cancels the edit.
- **Clearing.** With edits waiting, the bin's one brick pill reads "Clear bin · X" (the marked photos plus what the edits save), and the system alert says what happens: edited copies saved first, then the originals and photos deleted. While copies are made, "Saving edited video 1 of 2" sits above the buttons with ink `BristleTicks`, and the screen stays awake.

### The Library dashboard

Three parts, top to bottom, and nothing else: the hero, the bin, the library card. Each says one thing; no number appears twice.

- **Hero** (`HeroSection`), one `DashboardCard`. Space cleared as the brick serif 48 number, with no label over it. Under it, this week against last (`Format.weeklyChange`): brick when more was cleared, ink when less, since brick only means space freed and a drop isn't that (not `secondary`: it's essential small text); hidden when neither week cleared anything. The first time the tab is seen each launch, the number counts up from zero (`DS.Motion.countUpDuration` in `countUpSteps` numeric-text steps) and the change fades up once it lands; under Reduce Motion, and on later visits, both show at once. Then, as the card's content and its one visual, how far through the whole library the user is: the share reviewed in `title3` semibold with "reviewed" after it, `BristleTicks` in ink at `DS.Ticks.heroHeight`, and "11,050 of 17,820 photos reviewed" in footnote, all ink. It reads as one VoiceOver sentence. It shows whenever the library has anything in it, 0% included, so the goal is always there. On the entrance the bar fills from empty and the percent counts up in the same steps as the number, and the count under the bar fades up with the change. Before anything is cleared it's "Nothing cleared yet" with "Start reviewing", with the bar under it; the entrance still fills the bar once anything is reviewed.
- **Bin** (`BinCard`), right under the hero. Under limited access only, "Add more photos" and "Photo access" rows follow it.
- **Library card** (`LibraryCard`), "Review by type". A plain list, one row per focus with something in it: icon (`DS.LibraryList.iconWidth` column, hidden at accessibility sizes) · title · "count · size" · chevron, with `line` dividers, each row at least `DS.Tap.minimum` tall. The rows cover the library's kinds and what the analysis finds: duplicates, similar, accidental shots, blurry, screenshots, bursts and documents. Large videos aren't a row: they're already in Videos. Rows are biggest first, ties in `FocusTarget.listOrder`, and Saved for later always last. Tapping a row focuses the feed on it and does nothing else. A size is brick only when it's an amount to clear (duplicates and similar count only their extras, accidental shots, blurry, screenshots, bursts); the library's own kinds (videos, Live Photos, documents, photos) and what's saved for later are ink. While the library is still being analyzed the header says "Analyzing · 86%". At accessibility sizes the count and size stack under the title instead of truncating.

## Accessibility

- **Dynamic Type.** Custom sizes go through `dsSerif` or `@ScaledMetric`, and everything else uses text styles. Use `.minimumScaleFactor` only on single-line numbers (`ToClearCounter`). Use `.fixedSize(horizontal: false, vertical: true)` on wrapping copy. Every new screen gets a second `#Preview` at `.dynamicTypeSize(.xxLarge)`, as in `SettingsView`, and is checked at an accessibility size on device or in the simulator.
- **Tap targets.** The minimum is 44×44pt: `CircleIconButton` is 44, pills are at least 56 tall, tabs are at least 48. Small visual marks get `.contentShape` or padding so the target still reaches 44.
- **VoiceOver.** Label icon-only buttons. Combine compound values into one element with a sentence label (`ToClearCounter`, the pile's free-tier meter). Add `.accessibilityAddTraits(.isHeader)` to screen titles and eyebrows, and `.isSelected` to selected tabs. Post `AccessibilityNotification.Announcement` for results that arrive asynchronously ("Freed 38 MB"). Hide overlays and decoration (`SwipeOverlay`).
- **UI test IDs.** Use `accessibilityIdentifier("screen.element")`, for example `settings.done` or `caughtUp.checkAgain`.
- **Contrast** (WCAG 2.x, measured from the hex values):

  | Pair | Light | Dark | |
  |---|---|---|---|
  | `ink` on `paper` / `card` | 16.0 / 16.8 | 15.9 / 14.2 | AA |
  | `onInk` on `ink` | 17.1 | 15.9 | AA |
  | white on `brickFill` | 5.76 | 4.84 | AA |
  | `brick` on `paper` / `card` | 5.39 / 5.67 | 6.31 / 5.63 | AA |
  | `brick` on `brickTint` | 4.67 | 5.09 | AA |
  | `secondary` on `paper` / `card` | 6.63 / 6.97 | 7.06 / 6.29 | AA |
  | `line` on `paper` | 1.36 | 1.39 | decoration only |
  | `outline` on `paper` / `card` | 1.58 / 1.66 | 1.72 / 1.54 | decoration only; a control it rings must be clear from its fill or icon |

  Over the paper texture's lightest and darkest areas the worst cases are still AA: `ink` 14.5, `secondary` 6.0, `brick` 4.9 in light; 14.8, 6.6, 5.9 in dark. Recompute this table when a palette value changes.

## Do / don't

```swift
// Do                                             // Don't
.foregroundStyle(DS.Palette.brick)                .foregroundStyle(.red)  /  a hex color
.padding(.horizontal, DS.Spacing.l)               .padding(.horizontal, 20)
RoundedRectangle(cornerRadius: DS.Radius.inner,   RoundedRectangle(cornerRadius: 20)
                 style: .continuous)
.dsSerif(34, relativeTo: .largeTitle)             .font(.system(size: 34, design: .serif))
.font(.callout)                                   .font(.system(size: 16))
Button("Keep 3") {}.buttonStyle(.pill(.outline))  a hand-rolled Capsule().fill(...) button
withAnimation(DS.Motion.calm) { ... }             withAnimation(.easeInOut(duration: 0.3)) { ... }
Haptics.confirm()                                 UINotificationFeedbackGenerator()... in a view
.softShadow()                                     .shadow(color: .black.opacity(0.2), radius: 8)
Text(Format.size(bytes))                          Text("\(bytes / 1_000_000) MB")
```

- **Don't** use brick for Keep, navigation, links or "new" badges. It means deletion.
- **Don't** put more than one `.pill(.brick)` on a screen.
- **Don't** add a custom alert or confirmation UI. Use `.alert` and `.confirmationDialog`. The pile's delete confirmation is a system alert on purpose.
- **Don't** let a screen clip at large text. Make it scroll.

## Inconsistencies / TODO

These are known gaps in the code as of this file's first version. They're documented here, not fixed. Fix them in their own PRs, and remove each line when it's done.

- **The paper isn't behind every screen yet.** `RootView` has it; screens that still fill themselves with `paper` cover it. The A5 redesign moves them over screen by screen.
- **`AccentColor` asset is empty.** Tint is set view by view instead (`.tint(DS.Palette.ink)` in Settings, Library and Admin; `.tint(DS.Palette.secondary)` on progress views).
- **Literal paddings instead of `DS.Spacing`:**
  - 14, 18, 22 and 24 in the cards (`PhotoCardView`, `VideoCardView`, `DuplicatesCardView`, `SimilarShotsCardView`, `ScreenshotBatchCardView`, `CardContentView`, `SwipeableCard`, `SwipeHint`);
  - a list-row leading inset of 52 (`LibraryView`, `SettingsView`);
  - 26 in `PendingThumbnailGrid`, 20 in `FeedTopBar`, a top inset of 76 in `VideoPreviewView`, 28 in `PhotoAccessPrimerView`;
  - 14/8 in `Chip`, 10/3 in `ToClearCounter`'s pop chip, and 6 in `PendingPileView` badges.
- **58 literal `spacing:` values** in stacks across `Views/` and `DesignSystem/`.
- **A radius with no token:** 8 in `PendingThumbnailGrid` (`thumb` is 12).
- **Fixed-size fonts that don't scale with Dynamic Type:** 34 light in `LibraryAccessView`, 8 black in `SimilarShotsCardView`, 9 black and 20 in `PendingPileView`, 18 and 26 on the preview buttons (`PhotoPreviewView`, `VideoPreviewView`), and 18 in `CircleIconButton`.
- **Raw shadows outside the two modifiers:** black legibility shadows over media in `PendingPileView` and `VideoPreviewView`.
- **Raw animations outside `DS.Motion`:** `RootView` (2), `PhotoAccessPrimerView` (2), `OnboardingView`, `NotificationsPrimerView` and `SwipeableCard` (2).
- **Haptic outside `Haptics`:** `PendingPileView` uses `.sensoryFeedback(.selection, trigger:)`.
- **Duplicated toast:** `SettingsView` builds the same ink capsule toast twice instead of using `Toast`.
- **Press styles differ:** `PressScaleStyle` dims to 0.4 when disabled, and the tab bar's private `TabPressStyle` doesn't.
- **Two screen gutters:** 20 (`l`) in most screens and 28 (`xl`) in onboarding. The reason isn't written down.
- **Literal 44pt tap target:** `.frame(minHeight: 44)` in `FeedFocusChip`, where `DS.Tap.minimum` now exists.
- **`Chip` has no XXL preview.**
- **Debug-only exceptions:** `RankDebugBadge` uses a fixed font, black, and a radius of 6. It's Debug-only and can stay.
