# DESIGN.md — Bristle design system

This is how Bristle looks, moves and reads. It describes the code as it is. The tokens and components live in [`photo-swiper/photo-swiper/DesignSystem/`](photo-swiper/photo-swiper/DesignSystem/), under the `DS` namespace. **If this file and the code disagree, the code wins.** Fix this file in the same PR.

For UI work, load the `ios-ui` skill. To check a diff against this file, load `ui-review`. Both are in [`.claude/skills/`](.claude/skills/).

## Principles and tone

- **Warm and quiet.** The app uses paper-white surfaces, near-black ink and one accent. The photos are the color on screen, so the chrome stays out of their way.
- **Brick means "this goes away".** The accent marks deletion, amounts to clear and the celebration when space is freed, and nothing else. When something is brick, the user should read it as "this frees space".
- **Calm motion.** Springs settle with little bounce. Nothing loops for attention, and every flourish has a still fallback under Reduce Motion.
- **Serif for moments, system for work.** New York (`dsSerif`) is for headlines and big numbers. SF in system text styles is for everything you read or tap.
- **Plain words.** Copy is in sentence case and short sentences, with no exclamation marks and no dark patterns. Say what happens: "They'll stay in Recently Deleted for 30 days."
- **Private by design.** Nothing on screen implies a cloud. Don't add account, sync or sharing affordances.

## Color

Defined in `DS.Palette` ([`DesignSystem.swift`](photo-swiper/photo-swiper/DesignSystem/DesignSystem.swift)). Every token is a fixed sRGB hex built with `Color(hex:)`. Only `DesignSystem.swift` calls `Color(hex:)`.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#FAF7F2` | none | App and screen background. `LaunchBackground` in the asset catalog matches it. |
| `card` | `#FFFDF9` | none | Card surfaces, chip and neutral button fills, `UpsellCard`, tab bar. |
| `ink` | `#1F1B18` | none | Primary text, icons, `.pill(.ink)` fill, the selected tab, Keep. Also the usual `.tint`. |
| `secondary` | `#8A817A` | none | Supporting text, captions, inactive tabs, the outlined icon button. |
| `brick` | `#C24A3A` | none | Delete, amounts to clear, celebrations. **Never anything else.** |
| `brickTint` | `#F5E4DF` | none | Background behind brick content: the Delete circle, brick chips, the bin. |
| `line` | `#E9E3DB` | none | Hairlines, outlined buttons, empty progress tracks. |
| `muted` | `#EEE8E0` | none | Placeholder fill behind images while they load. |
| `shadow` | `#4A382B` | none | Shadow color only, used at low opacity through `cardShadow()` and `softShadow()`. |

**Fixed white and black** are allowed in only two places: over photos and video (preview chrome, card captions, scrims, `Chip(.frosted)`), and as text or icons on an `ink` or `brick` fill.

**Dark mode doesn't exist yet.** No token has a dark value, and the app doesn't set `UIUserInterfaceStyle`, so it follows the system appearance. In dark mode, alerts, confirmation dialogs, the keyboard and the Safari sheet turn dark while every app surface stays light. The full-screen previews ([`PhotoPreviewView`](photo-swiper/photo-swiper/Views/Preview/PhotoPreviewView.swift), [`VideoPreviewView`](photo-swiper/photo-swiper/Views/Preview/VideoPreviewView.swift)) and `Chip(.frosted)` force `.dark` on purpose, because they sit on media. The plan for dark mode is to give each `DS.Palette` name a dark value (an asset-catalog color set, or a dynamic `UIColor`) behind the same name, so call sites don't change. Until then, new UI must use the tokens so that it picks up dark values when they land.

## Typography

**Serif:** `.dsSerif(size, relativeTo:weight:italic:)` sets New York at a design size through `@ScaledMetric`, so it still scales with Dynamic Type. Always pass the `relativeTo` text style the size stands in for. The sizes in use:

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

**Elevation** has two levels, both warm:

- `cardShadow()`: a soft two-layer lift for cards and stamp discs.
- `softShadow()`: lighter, for chips, `PillTabBar` and `UpsellCard`.

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
| `countUpDuration`, `countUpSteps` | The dashboard's space cleared counting up from zero: once per launch, in steps of `calm` numeric-text changes, easing out |

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
| `Chip` | Small rounded labels. `.brick` for counts tied to clearing (swipes left), `.plain` for neutral markers over imagery (Best pick, Keep) and the feed's focus ("Only large videos ×", with `trailingSystemImage: "xmark"`, which takes the text color), `.frosted` for text over video. A row of single-select choices uses `.option` (ink on card in a `line` outline) and `.selected` (white on ink), each in a button at least `DS.Tap.minimum` tall with the `.isSelected` trait on the chosen one. |
| `PillTabBar` | The floating tab bar. Its selection animates with `DS.Motion.tab` and fires `Haptics.tabChange`. |
| `ProgressLine` | A thin progress track. Ink by default, brick for amounts to clear. It reads its percentage to VoiceOver. |
| `ToClearCounter` | The brick serif running total, with a "+3.4 MB" chip that pops above it. |
| `UpsellLayout` / `UpsellCard` / `IncludedRow` | Every unlock surface (the wall and the sheets), so they read as one offer. |
| `ConfettiView` | The celebration after freeing space. It never takes touches, announces `message`, and falls back to a note under Reduce Motion. |
| `OpenSettingsButton` | Any link to the app's page in iOS Settings (permissions). |
| `SwipeStamp` (in `Views/Feed/`) | The Delete, Keep and Later wash over a card. It's also used in onboarding's demo. |
| `DashboardCard` | A dashboard panel: a header view, then content, on a `card` panel at `Radius.inner` with `softShadow()` on the shape. The library card uses it. |
| `BinCard` | The pile on the dashboard, drawn as a brick bin (it's what will be deleted), sized by `DS.Bin`. With a free limit the bin fills against it ("56.6 MB of 64 MB", "Full at …" when full); unlocked, the first `DS.Bin.stackCount` photos fan out over the rim. Empty, it stays and says so in ink. Wrap it in the link to the pile only when there's something in it: a disabled link would dim its text. One VoiceOver sentence. |

Formatting goes through `Format` (`size`, `signedSize`, `percent`, `signedPercent`, `weeklyChange`, `day`, `shortDay`, `shortMonth`, `range`, `duration`, `countdown`, `roughDays`, `spelled`, `count`). `size` uses `ByteCountFormatter` in decimal units from MB up, as Photos and Settings do ("1.2 GB", "0.1 MB"), and reads "0 MB" for nothing. `signedPercent` has one decimal ("+34.5%", "−25.0%"); `weeklyChange` reads "+1.2 GB (+34.5%) vs last week", or "+1.2 GB this week" when last week cleared nothing.

### The Library dashboard

Three parts, top to bottom, and nothing else: the hero, the bin, the library card. Each says one thing; no number appears twice.

- **Hero** (`HeroSection`). Space cleared as the brick serif 48 number, with no label over it. Under it, this week against last (`Format.weeklyChange`): brick when more was cleared, `secondary` when less, since brick only means space freed and a drop isn't that; hidden when neither week cleared anything. The first time the tab is seen each launch, the number counts up from zero (`DS.Motion.countUpDuration` in `countUpSteps` numeric-text steps) and the change fades up once it lands; under Reduce Motion, and on later visits, both show at once. Before anything is cleared it's "Nothing cleared yet" with "Start reviewing". Below, the review heatmap.
- **Bin** (`BinCard`), right under the hero. Under limited access only, "Add more photos" and "Photo access" rows follow it.
- **Library card** (`LibraryCard`). Header: the share reviewed, with a `ProgressLine`. Then the composition bar with its key, then one row of single-select chips (Duplicates, Similar, Large videos, Videos, Live Photos, Screenshots, Bursts, Saved for later; empty ones hidden), which scrolls sideways. The first chip selected has the most space to recover. The selected chip lights up its slice of the bar (in ink, the others in `line`) and shows its count, its size, a strip of its five biggest items (`DS.LibraryCard.thumbSize` at most, sharing the width) and "Review these", which focuses the feed. A size is brick only when it's an amount to clear (duplicates and similar count only their extras, large videos, screenshots, bursts); the library's own kinds and what's saved for later are ink.

### Charts

The dashboard's two small charts are drawn with SwiftUI shapes from `DS.Chart`, and read as one family:

- **No category colors.** The photos are the color in this app, and brick means deletion. Anything that isn't space cleared is ink.
- **The composition bar** is one stacked bar in ink shades (`DS.Chart.categoryOpacities`, biggest first) with `DS.Chart.segmentGap` between segments, `DS.Chart.stackedBarHeight` tall through `@ScaledMetric`, in a `Capsule()`. A key gives each segment a `DS.Chart.swatchSize` swatch, a name and a size, so a shade never says what something is on its own. VoiceOver reads the breakdown as one sentence.
- **The review heatmap** (`ReviewHeatmap`) is a grid of `DS.Chart.heatCellSize` cells with `heatCellGap` and `heatCellRadius`, a column per week over 16 weeks, counting photos reviewed (keeps included). Level 0 is `line`, then ink at `DS.Chart.heatOpacities`. It has a "Less … More" key, a caption with the total, and one VoiceOver summary. When the cells, scaled with text, don't fit, the grid scrolls sideways (`ViewThatFits`) with the latest week in view; it never widens the page. No streak: a missed day costs nothing.

## Accessibility

- **Dynamic Type.** Custom sizes go through `dsSerif` or `@ScaledMetric`, and everything else uses text styles. Use `.minimumScaleFactor` only on single-line numbers (`ToClearCounter`). Use `.fixedSize(horizontal: false, vertical: true)` on wrapping copy. Every new screen gets a second `#Preview` at `.dynamicTypeSize(.xxLarge)`, as in `SettingsView`, and is checked at an accessibility size on device or in the simulator.
- **Tap targets.** The minimum is 44×44pt: `CircleIconButton` is 44, pills are at least 56 tall, tabs are at least 48. Small visual marks get `.contentShape` or padding so the target still reaches 44.
- **VoiceOver.** Label icon-only buttons. Combine compound values into one element with a sentence label (`ToClearCounter`, the pile's free-tier meter). Add `.accessibilityAddTraits(.isHeader)` to screen titles and eyebrows, and `.isSelected` to selected tabs. Post `AccessibilityNotification.Announcement` for results that arrive asynchronously ("Freed 38 MB"). Hide overlays and decoration (`SwipeOverlay`).
- **UI test IDs.** Use `accessibilityIdentifier("screen.element")`, for example `settings.done` or `caughtUp.checkAgain`.
- **Contrast** (WCAG 2.x, measured from the hex values):

  | Pair | Ratio | |
  |---|---|---|
  | `ink` on `paper` / `card` | 16.0 / 16.8 | AA |
  | white on `ink` | 17.1 | AA |
  | white on `brick` | 4.84 | AA |
  | `brick` on `paper` | 4.53 | AA (just) |
  | `brick` on `brickTint` | 3.93 | **large text only** |
  | `secondary` on `paper` / `card` | 3.57 / 3.76 | **large text only** |
  | `line` on `paper` | 1.19 | decoration only; don't rely on it to convey anything |

  Don't use `secondary` or brick-on-tint for essential small text in new UI. This is a known gap, listed below.

## Do / don't

```swift
// Do                                             // Don't
.foregroundStyle(DS.Palette.brick)                .foregroundStyle(.red)  /  Color(hex: 0xC24A3A)
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

- **No dark mode.** Tokens have no dark values, and the app follows the system appearance, so in dark mode its light surfaces sit beside dark system alerts, dialogs and the keyboard.
- **`AccentColor` asset is empty.** Tint is set view by view instead (`.tint(DS.Palette.ink)` in Settings, Library and Admin; `.tint(DS.Palette.secondary)` on progress views).
- **Contrast below AA for small text:** `secondary` on `paper`/`card` (3.57/3.76), used widely for captions; `brick` on `brickTint` (3.93), for example `Chip(.brick)` at `.caption`.
- **Literal paddings instead of `DS.Spacing`:**
  - 14, 18, 22 and 24 in the cards (`PhotoCardView`, `VideoCardView`, `DuplicatesCardView`, `SimilarShotsCardView`, `ScreenshotBatchCardView`, `CardContentView`, `SwipeableCard`, `SwipeHint`);
  - a list-row leading inset of 52 (`LibraryView`, `SettingsView`);
  - 26 in `PendingThumbnailGrid`, 20 in `FeedTopBar`, a top inset of 76 in `VideoPreviewView`, 28 in `PhotoAccessPrimerView`;
  - 14/8 in `Chip`, 10/3 in `ToClearCounter`'s pop chip, and 6 in `PendingPileView` badges.
- **58 literal `spacing:` values** in stacks across `Views/` and `DesignSystem/`.
- **A radius with no token:** 8 in `PendingThumbnailGrid` (`thumb` is 12).
- **Fixed-size fonts that don't scale with Dynamic Type:** 34 light in `LibraryAccessView`, 8 black in `SimilarShotsCardView`, 9 black and 20 in `PendingPileView`, 18 and 26 on the preview buttons (`PhotoPreviewView`, `VideoPreviewView`), and 18 in `CircleIconButton`.
- **Raw shadows outside the two modifiers:** a third style in `ScreenshotBatchCardView` (radius 14, y 10), and black shadows in `PendingPileView` and `VideoPreviewView`.
- **Raw animations outside `DS.Motion`:** `RootView` (2), `PhotoAccessPrimerView` (2), `OnboardingView`, `NotificationsPrimerView` and `SwipeableCard` (2).
- **Haptic outside `Haptics`:** `PendingPileView` uses `.sensoryFeedback(.selection, trigger:)`.
- **Duplicated toast:** `SettingsView` builds the same ink capsule toast twice, and there's no shared component.
- **Press styles differ:** `PressScaleStyle` dims to 0.4 when disabled, and the tab bar's private `TabPressStyle` doesn't.
- **Two screen gutters:** 20 (`l`) in most screens and 28 (`xl`) in onboarding. The reason isn't written down.
- **Literal 44pt tap target:** `.frame(minHeight: 44)` in `FeedFocusChip`, where `DS.Tap.minimum` now exists.
- **`Chip` has no XXL preview.**
- **Debug-only exceptions:** `RankDebugBadge` uses a fixed font, black, and a radius of 6. It's Debug-only and can stay.
