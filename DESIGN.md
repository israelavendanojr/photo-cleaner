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
| `scrim` | `#1F1B18` | `#1F1B18` | The dark wash under a caption on a photo (`BottomScrim`). The same in both modes: it sits on the picture. |

**Fixed white and black** are allowed in only two places: over photos and video (preview chrome, card captions, scrims, `Chip(.frosted)`), and white on `brickFill`. On an `ink` fill use `onInk`.

**The paper.** Every screen sits on `PaperBackground` (`.paperBackground()`): the `paper` color under the `Paper` image, a creased-paper texture with a light and a dark version. It fills the screen under the safe areas, keeps its proportions, and never moves. Don't put an opaque `paper` fill over it at screen level. A sheet takes it with `.presentationBackground { PaperBackground() }`. A bar pinned over scrolling content (onboarding's footer, the pile's actions) uses `PaperBackground(alignment: .bottom)`, which lines its paper up with the screen's so the bar has no edge of its own. Navigation bars keep a flat `paper` toolbar background, so titles stay readable over scrolled content.

**Forced dark.** The full-screen previews ([`PhotoPreviewView`](photo-swiper/photo-swiper/Views/Preview/PhotoPreviewView.swift), [`VideoPreviewView`](photo-swiper/photo-swiper/Views/Preview/VideoPreviewView.swift)) and `Chip(.frosted)` force `.dark` on purpose, because they sit on media.

## Typography

**Serif:** `.dsSerif(size, relativeTo:weight:italic:)` sets Newsreader at a design size through `@ScaledMetric`, so it still scales with Dynamic Type. Newsreader is bundled (`Resources/Fonts/`, two variable fonts under the SIL Open Font License, whose text ships beside them) and listed in `UIAppFonts`; `DS.Serif` sets its weight and optical-size axes, and falls back to New York if it didn't load. Always pass the `relativeTo` text style the size stands in for. The sizes in use:

| Size | `relativeTo` | Weight | Where |
|---|---|---|---|
| 84 | `.largeTitle` | regular | The dashboard's space cleared (brick), its unit beside it at 34 |
| 48 | `.largeTitle` | regular | Big numbers: pile total, a video card's file size |
| 46 | `.largeTitle` | medium | Welcome headline |
| 40 | `.largeTitle` | medium | Onboarding page titles |
| 38 | `.largeTitle` | regular | A plan's price on the paywall |
| 36 | `.largeTitle` | medium | The paywall's headline |
| 34 | `.largeTitle` | medium | Screen titles (pile, Admin); regular on empty states ("Nothing cleared yet") |
| 34 | `.title` | regular | `ToClearCounter` (brick) |
| 28 | `.title` | regular | Photo card date |
| 24 | `.title2` | medium | The wordmark, beside `BristleMark` |
| 22 | `.title3` | regular, *italic* for group cards; medium for the Library's list headers | Similar and duplicate card titles |
| 20 | `.title3` | regular | Video card date |
| 19 | `.headline` | medium | Navigation-bar title (Settings) |

**System:** everything else uses semantic text styles, never `.font(.system(size:))`:

- `.headline` for button labels (`PillButtonStyle`) and toolbar buttons
- `.body` / `.callout` for reading text; `.callout` for supporting sentences under a headline
- `.subheadline` for eyebrows, chips and tab labels (`.semibold` where it's a control)
- `.footnote` / `.caption` / `.caption2` for metadata, captions and badges

Numbers that change use `.monospacedDigit()` and `.contentTransition(.numericText(value:))`. Format every size, date, duration, count and percentage with `Format` ([`Formatting.swift`](photo-swiper/photo-swiper/DesignSystem/Formatting.swift)), never inline. That includes chart axis labels.

## Spacing and layout

`DS.Spacing`: `xxs` 4 · `xs` 8 · `s` 12 · `m` 16 · `l` 20 · `xl` 28 · `xxl` 40, plus `cardInset` 28, which is the card stack's inset from the screen edge: wide enough that the tilted cards behind the top one stay on screen.

- **Screen gutter:** `l` (20) horizontally on most screens. Onboarding uses `xl` (28) through `onboardingLayout`.
- **Stack spacing:** `xs` inside a group, `s`–`m` between rows, `l`–`xl` between sections.
- **Large text scrolls, it doesn't clip.** Put content in a `ScrollView` with `.scrollBounceBehavior(.basedOnSize)`, and pin the primary action below it. Two layouts already do this:
  - `onboardingLayout(footerOrder:footer:)` ([`OnboardingEntrance.swift`](photo-swiper/photo-swiper/Views/Onboarding/OnboardingEntrance.swift)) for onboarding pages;
  - `PaywallView` ([`PaywallView.swift`](photo-swiper/photo-swiper/Views/Session/PaywallView.swift)) for the paywall: its content scrolls and the buy button, billing note and Restore stay under it.
- Full-width buttons are `.frame(maxWidth: .infinity)`, which `PillButtonStyle` already applies. Side-by-side pills share an `HStack(spacing: DS.Spacing.s)`.

## Corner radius and elevation

`DS.Radius`: `card` 28 · `inner` 24 · `tile` 16 · `thumb` 12. Always use `RoundedRectangle(cornerRadius:style: .continuous)`. Pills, chips, toasts and tab bars are `Capsule()`, and round buttons are `Circle()`.

| Radius | For |
|---|---|
| `card` | Feed cards and anything clipped to them (`SwipeOverlay`) |
| `inner` | Panels inside a screen, image areas inside a card |
| `tile` | Grid tiles and smaller grouped surfaces |
| `thumb` | Thumbnails |

**Elevation** has two levels. Each is a tight contact line under a short drop, so a surface reads as paper lying on paper; the values are in `DS.Shadow`, heavier in dark mode, where a soft shadow wouldn't show.

- `cardShadow()`: cards, photos and stamp discs.
- `softShadow()`: chips and `PillTabBar`. `softShadow(raised: true)` is a touch firmer, for a surface that's a choice.

Put the shadow on the background shape, not on the view that holds text, so the text doesn't get a halo (the paywall's plan cards show the pattern). The only material is `.ultraThinMaterial`, used for controls over media.

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
| `stackSettle` | The loose stack after a swipe: the next card straightening as it comes to the top |
| `rowStagger` | The beat between one Library row fading up and the next, once per launch |
| `fan` | The paywall's three photos fanning out from a squared pile as it appears |
| `planSelect` | The paywall's selection moving between plans |
| `tickFill` | `BristleTicks` sweeping to a new value, tick by tick |
| `countUpDuration`, `countUpSteps` | The dashboard's space cleared counting up from zero, and its ticks filling from empty alongside: once per launch, in steps of `calm` changes, easing out |

**Reduce Motion:** read `@Environment(\.accessibilityReduceMotion)` and show the end state at once, or swap movement for a fade. Examples: `OnboardingEntrance`, `DealIn`, `SwipeableCard` (no nudges), `ConfettiView` (a fading note instead of confetti), `StackedPhotosIllustration`.

**Haptics** come from `Haptics` ([`Haptics.swift`](photo-swiper/photo-swiper/DesignSystem/Haptics.swift)), with one function per moment: `threshold`, `advance` (also a dashboard suggestion tapped), `accessGranted`, `delete`, `refused`, `confirm`, `unlocked`, `tabChange`, `planChosen` (a different plan picked on the paywall), `refreshed` (pull to refresh finished). A new moment gets a new function there. Views don't create `UI*FeedbackGenerator`s or use `.sensoryFeedback` directly.

## Components

All of these are in [`DesignSystem/Components/`](photo-swiper/photo-swiper/DesignSystem/Components/), and each has a `#Preview`. Check this list before building something new.

| Component | Use when |
|---|---|
| `PillButtonStyle`, applied as `.buttonStyle(.pill(_:))` | Any full-width action. `.ink` is the primary action, `.brick` is reserved for the destructive or paid primary (Delete N, Unlock), `.outline` is secondary, `.ghost` is tertiary ("Not now"). One brick button per screen at most. |
| `CircleActionButton` | The feed's round action-bar buttons with a caption. `.destructive` (brick on tint) for Delete, `.neutral` (card with an `outline` ring) for Later, `.primary` (a filled `ink` disc with an `onInk` icon) for Keep. |
| `CircleIconButton` | The 44pt icon button in top bars (Undo, Close, Settings): an ink icon on `card` with an `outline` ring. Requires `accessibilityLabel`. |
| `PressScaleStyle` | The press-down scale for custom icon buttons. It also dims the button when disabled. |
| `Chip` | Small rounded labels. `.brick` for counts tied to clearing, `.plain` for the feed's filter pill ("Videos ⌄", with `trailingSystemImage: "chevron.down"`, which takes the text color), `.onPhoto` for a label lying on a picture (Best pick, Keep): a pale slip with dark text in both appearances. `.frosted` for text over video. |
| `PillTabBar` | The floating tab bar: text-only tabs (`DS.TabBar`), the selected one on an ink capsule. Its selection animates with `DS.Motion.tab` and fires `Haptics.tabChange`. |
| `BristleTicks` | Any progress or proportion: upright 2pt strokes on a 5pt pitch (`DS.Ticks`), the filled part over an `outline` track, drawn in a `Canvas`. Ink by default, brick for amounts to clear. `showsTrack: false` for a bar that only compares sizes; `popsNew` lifts ticks as they fill. It fills tick by tick, from empty the first time it's seen (at once under Reduce Motion), scales its height with Dynamic Type, and reads its percentage to VoiceOver: give it a label where it's used. Onboarding's step progress is one too. `BristleMark` is the glyph made from it, for the wordmark. |
| `ToClearCounter` | The brick serif running total with its label on the same baseline ("184 MB of 1 GB"; the label drops under it where they don't fit), and a "+3.4 MB" chip that pops above it. Unlocked, it's the whole bin, edits included; with a free limit it's the deletes the limit counts. |
| `Toast` | A short note in an ink `Capsule()` with an optional underlined action, announced to VoiceOver, e.g. the feed's "Edit queued · saves ~335 MB · Undo". The caller decides how long it stays. |
| `PaywallView` (in `Views/Session/`) | Every place the unlock is offered: the swipe wall, after a free user's delete, Settings and onboarding's last step show this one screen. See "The paywall" below. |
| `ConfettiView` | The celebration after freeing space. It never takes touches, announces `message`, and falls back to a note under Reduce Motion. |
| `OpenSettingsButton` | Any link to the app's page in iOS Settings (permissions). |
| `SwipeStamp` (in `Views/Feed/`) | The Delete, Keep and Later wash over a card. It's also used in onboarding's demo. |
| `FeedFilterMenu` (in `Views/Feed/`) | The filter's menu, our paper dropdown rather than a system `Menu`: a `card` surface at `DS.Radius.inner` with `softShadow(raised: true)`, at most `DS.Popup.maxWidth`, opening under the top bar at its leading edge, over the deck. Ruled rows of names only (Everything, then `FocusTarget.filterOrder`), at least `DS.Tap.minimum` tall, with an ink checkmark on the current one. It scrolls when it doesn't fit, fades in (just a fade under Reduce Motion), plays `Haptics.tabChange` on a choice, and closes on a tap outside or VoiceOver's escape; it's modal to VoiceOver and the deck takes no swipes while it's open. |
| `Rule` | A hairline in `line`. Lists on the paper are ruled, not boxed: a `Rule` above each row and one after the last. |
| `TallyRow` | A ruled row that tallies one thing: name and count, a short run of ticks for its share (`DS.Tally`), its size, a chevron. Brick when the size is an amount to clear, ink otherwise. At accessibility sizes the count, size and ticks go under the name. |
| `BinRow` (in `Views/Library/`) | The pile on the dashboard, one `TallyRow` between rules: "Bin", how many, their size, in brick. With a free limit its ticks show the pile against it, over a track, and once full it says "Full at 1 GB. Delete these to keep clearing." Empty, it looks the same with zeros and no chevron. Wrap it in the link to the pile only when there's something in it: a disabled link would dim its text. One VoiceOver sentence. |

Formatting goes through `Format` (`size`, `signedSize`, `percent`, `signedPercent`, `weeklyChange`, `day`, `shortDay`, `range`, `duration`, `countdown`, `roughDays`, `spelled`, `count`). `size` uses `ByteCountFormatter` in decimal units from MB up, as Photos and Settings do ("1.2 GB", "0.1 MB"), and reads "0 MB" for nothing. `signedPercent` has one decimal ("+34.5%", "−25.0%"); `weeklyChange` reads "+1.2 GB (+34.5%) vs last week", or "+1.2 GB this week" when last week cleared nothing.

### The feed

- **Top bar** (`FeedTopBar`): Undo on the left, then the filter pill, and the `ToClearCounter` on the right, which opens the pile. The pill (`FeedFilterPill`, a `.plain` `Chip` with `chevron.down`) reads "Everything" or the focus's short title ("Videos"); where the name doesn't fit (accessibility sizes) a `line.3.horizontal.decrease` icon stands in for it rather than push the counter, and it's hidden when the filter is off for the plan. Tapping it opens the filter menu, or the paywall when the filter is locked and nothing is focused. A focused feed always shows the pill and its menu, whatever the plan, so Everything is always a way back; there, while locked, the other choices open the paywall, and while off, only Everything is offered. There's no swipes-left pill: the wall says it at zero. "Still scanning · N%" is in Settings, under Feed, once the Library has worked it out. For a free user the pile's meter runs under it: brick `BristleTicks` at the pile's share of the free limit, with "Free pile" and "12 photos waiting" beneath, one VoiceOver sentence. The new ticks pop when a photo is piled. Unlocked, there's no limit and no meter.
- **The loose stack** (`SwipeDeck`, `StackedBehind`, `DS.Stack`): the next two cards lie behind the top one as real cards, each tilted a few degrees and a step dimmer, the nearer one nudged out from under the top. A card's tilt comes from its ID (`StackPose.tilt`), so it never changes between renders or launches. As the top card is dragged, the cards behind move a step forward in proportion: the next straightens and brightens. On fly-out it settles to 0° (`DS.Motion.stackSettle`) and a new card fades in at the back; undo runs it backward. With Reduce Motion the cards behind hold still during the drag. It's drawing only: the deck's order and which card a swipe decides are the view model's. Only the top card is in the accessibility tree.
- **Action bar:** Delete (brick on tint), Later (smaller, ringed), Keep (the filled ink disc).
- **Photo card:** the date in serif over the scrim, place and size under it. A flagged photo shows no flag on its card (`testFlaggedPhotoCardShowsNoFlag`).

### The paywall

One screen (`PaywallView`, `DS.Paywall`), the same on every surface, so the offer never reads differently depending on how the user got there. Top to bottom:

- **Close** (`xmark`), top left. Onboarding hides it: its own top bar has the way out.
- **Hero:** three photos in a loose pile, each with `cardShadow()`. They start squared up and fan out as the screen appears (`DS.Motion.fan`); with Reduce Motion they're simply fanned.
- **Headline** "Clear without limits." in serif 36, and one supporting sentence in `secondary`, both centred.
- **Benefits:** ruled rows (`Rule`), each an icon, a title and a line. Every one must be true in code; `UnlockCopy.benefits` says how each was checked, and `UpsellCopyTests` holds them to it.
- **Plans:** one card per plan the store lists (`vm.unlockPlans`), side by side, stacked at accessibility sizes: the plan's name, its price in serif 38, and how it's paid. The chosen card has an `ink` ring and a filled mark; the others an `outline` ring and an empty one. Choosing moves with `DS.Motion.planSelect` and `Haptics.planChosen`. Prices are the store's localized strings, never written in the app. A plan appears only once the store has given its price; with none to show, the cards give way to "Loading prices…" and then "Couldn't load prices from the App Store." with an outline "Try again", and there is no buy button.
- **Under the scroll:** the screen's one `.pill(.brick)`, naming the chosen plan and price ("Unlock for $9.99", "Subscribe for $4.99 / month"), then how that plan is billed with Restore beside it (for the subscription: its name, price, period, that it renews, and where to cancel), then Privacy and Terms. A failed purchase or restore explains itself in one line under the button.

It has no "Not now": Close is the way out. It says nothing about when free swipes come back.

### The full-screen video, its trim strip and compression

`VideoPreviewView`, after Photos' video editor without its tool tabs or Cancel/Done. It's forced dark and sits on black, so fixed white and black are allowed here (see Color).

- **Top bar:** round frosted (`.ultraThinMaterial`) 44pt buttons, Close and volume on the left, the size and short date in the middle, and Compress (`arrow.down.right.and.arrow.up.left`) on the right. Compress turns brick once a level is set, like the strip once trimmed. Where it isn't offered (compression off, slow-motion, Cinematic) its slot stays empty, so nothing moves.
- **`CompressionPopup`**, a centred frosted card over the video (`.ultraThinMaterial`, dark, white text, `DS.Radius.card`, at most `DS.Popup.maxWidth` wide), in the style of the viewer's other controls. It's a deliberate custom popup rather than a system sheet: the video stays visible, live and holdable around it, with no scrim. "Compress" and a line on what it does, a round frosted close button (`FrostedIconButton`, `xmark`) beside them, then None / Light / Balanced / Max as rows on a lighter frost (white at 12%) at `DS.Radius.tile` (a `checkmark.circle.fill` on the choice, the level's caption under its name: "Original quality", "Looks the same", none, "Fine on a phone"), each with "380 MB → ~120 MB" after the trim, and Apply as a brick capsule like Save. A level that saves under 10% is at 40% opacity and reads "Already small". It scales in (fades with Reduce Motion); the close button, Apply, a tap on the video outside it, or VoiceOver's escape closes it. At large text its rows scroll inside the card. Choosing a level previews it: "Preview · Balanced" as a frosted `Chip` where the 2x pill goes, with a small white spinner while it encodes, and "Original" while the video is held.
- **Bottom bar:** one flat bar, as in Photos, with nothing around it: the play button on a frosted segment, a black hairline, then `TrimStrip` at the same height. Its outer corners are `DS.Trim.cornerRadius`. The play button sits above the strip, so the start handle's touch area never takes its taps.
- **`TrimStrip`** (`DS.Trim`): stills across the clip at `stripHeight` (scaled), a white `playheadWidth` playhead, and chevron handles of `handleWidth` outside the stills, each reaching a 44pt touch area outward. Untrimmed, there's no frame: white chevrons sit on the same frosted ground as the play button, so the bar reads as one piece. Once a handle moves, the frame (`frameWidth`) and handles turn brick (space to clear), and what's cut is dimmed with black. With no handles (short clips, slow-motion, Cinematic, trimmer off) it's a plain seek bar.
- **Edit summary**, above the panel once trimmed or compressed: "0:08 · 1.23 GB → 0:05 · ~752 MB" in footnote semibold, "saves ~476 MB" (trim and compression together) in subheadline bold under it, and while the edit differs from what's saved, Reset (frosted capsule) and Save (brick capsule), both 44pt tall.
- **Leaving** with an unsaved trim or level uses a system `.confirmationDialog`, "Save changes?": Save changes, Discard (destructive), Keep editing (cancel).

### The full-screen photo and Live Photos

`PhotoPreviewView`, forced dark like the video. Its top bar is the round frosted Close, then, for a Live Photo, a frosted `Chip` reading "LIVE" with `livephoto`, and the size, place and date on the right. Pressing and holding a Live Photo plays its motion with sound (`LivePhotoPlayer`) and a light haptic, like the video's 2x; letting go goes back to the still. While the motion is still downloading, "Loading Live Photo" sits where the 2x pill goes (`DS.Preview.pillTop`, shared by every status pill in the viewers), as a frosted `Chip` with a small white spinner. VoiceOver's "Play Live Photo" action plays it once through.

Where flattening is offered (JUN-79), a bottom bar over a dark gradient, like the video editor's summary, reads "Live Photo · 4.5 MB → ~1.8 MB" (footnote semibold) over "saves ~2.7 MB" (subheadline bold), white, with a brick `TrimButtonStyle` "Flatten" capsule beside them: it clears space, like Save. Locked, Flatten opens `UnlockSheet` over the viewer. Flatten closes the viewer, and the card flies off right with a "Flatten queued · saves ~X · Undo" toast.

### The bin's edits and clearing

- **Edits section** in `PendingPileView`, under the photo grid: one `EditRow` per video on `card` at `DS.Radius.tile`, with the thumbnail, then the marks ("Trimmed", "Compressed · Balanced", or both) as `caption` semibold ink labels with their symbols, the change ("1:42 → 0:12 · 380 MB → ~45 MB") in subheadline semibold, and "saves ~X" in brick footnote. Swiping a row left cancels the edit.
- **Flattens section**, under Edits: the same `EditRow`, marked "Flattened" (`livephoto.slash`), with "Live Photo · 4.1 MB → ~1.7 MB" as the change and "saves ~X". Swiping a row left, or "Cancel flatten", keeps the Live Photo as it is. The summary counts both ("to clear from 12 photos, 2 edits and 1 flatten"), and the alert names them ("Saves 2 edited videos and 1 flattened photo, then deletes their originals…").
- **Clearing.** With edits waiting, the bin's one brick pill reads "Clear bin · X" (the marked photos plus what the edits save), and the system alert says what happens: edited copies saved first, then the originals and photos deleted. While copies are made, "Saving edited video 1 of 2" sits above the buttons with ink `BristleTicks`, and the screen stays awake.

### The Library dashboard

Straight on the paper, no cards. Top to bottom: the wordmark, the hero, the bin, Top Categories. Each says one thing.

- **Header:** `BristleMark` and the app's name in serif 24, with Settings (`gearshape`) on the right.
- **Hero** (`HeroSection`): "Cleared so far", then space cleared as the brick serif 84 number with its unit at 34. Under it, this week against last (`Format.weeklyChange`) in ink, up or down; hidden when neither week cleared anything. The first time the tab is seen each launch, the number counts up from zero (`DS.Motion.countUpDuration` in `countUpSteps` numeric-text steps) and the change fades up once it lands; under Reduce Motion, and on later visits, both show at once. Then how far through the whole library the user is: "21% reviewed" and "3,740 of 17,820 photos" on one baseline, over `BristleTicks` in ink at `DS.Ticks.heroHeight`. It reads as one VoiceOver sentence, and shows whenever the library has anything in it, 0% included. On the entrance the ticks fill from empty with the number. Before anything is cleared it's "Nothing cleared yet" with "Start reviewing".
- **Bin** (`BinRow`), under the hero. Under limited access only, "Add more photos" and "Photo access" follow it as ruled rows.
- **"Top Categories"** (`LibraryList`, JUN-88): a serif header, then one ink `TallyRow` for each of the few kinds taking the most space that are worth a look (`DashboardSnapshot.topCategories`): duplicates, similar, accidental, blurry, videos, Live Photos, screenshots, bursts, documents. Photos, saved for later and large videos are never in it. Three by default (Admin Tools → Top Categories), biggest first, a row's ticks its size against the biggest. No total: the kinds overlap, so they don't add up. The rows are ink, though some are amounts to clear: the section mixes kinds of thing with amounts, and brick stays for the bin. While the library is still being analyzed, "Analyzing · 86%" sits under the header. With nothing to show, "Nothing obvious left to clear.", or "Still looking through your library. Suggestions show up as it's analyzed." while it's being analyzed.
- Tapping a row focuses the feed on it and switches to the Feed tab. While Top Categories is locked for the plan, only the first rows do (one by default); the rest open the paywall. Locked rows look the same as the others, with no lock: the paywall explains itself, and VoiceOver's hint says "Unlock to show only …". Off, the section isn't shown. The first time the rows are seen each launch they fade up one after another (`DS.Motion.rowStagger`); still under Reduce Motion.

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

- **`AccentColor` asset is empty.** Tint is set view by view instead (`.tint(DS.Palette.ink)` in Settings, Library and Admin; `.tint(DS.Palette.secondary)` on progress views).
- **Literal paddings instead of `DS.Spacing`:**
  - 14, 18, 22 and 24 in the cards (`VideoCardView`, `DuplicatesCardView`, `SimilarShotsCardView`, `ScreenshotBatchCardView`, `CardContentView`, `SwipeableCard`, `SwipeHint`);
  - a list-row leading inset of 52 (`SettingsView`);
  - 26 in `PendingThumbnailGrid`, a top inset of 76 in `VideoPreviewView`, 28 in `PhotoAccessPrimerView`;
  - 14/8 in `Chip`, and 6 in `PendingPileView` badges.
- **58 literal `spacing:` values** in stacks across `Views/` and `DesignSystem/`.
- **A radius with no token:** 8 in `PendingThumbnailGrid` (`thumb` is 12).
- **Fixed-size fonts that don't scale with Dynamic Type:** 34 light in `LibraryAccessView`, 8 black in `SimilarShotsCardView`, 9 black and 20 in `PendingPileView`, and 18 and 26 on the preview buttons (`PhotoPreviewView`, `VideoPreviewView`).
- **Raw shadows outside the two modifiers:** black legibility shadows over media in `PendingPileView` and `VideoPreviewView`.
- **Raw animations outside `DS.Motion`:** `RootView` (2), `PhotoAccessPrimerView` (2), `OnboardingView`, `NotificationsPrimerView` and `SwipeableCard` (2).
- **Haptic outside `Haptics`:** `PendingPileView` uses `.sensoryFeedback(.selection, trigger:)`.
- **Duplicated toast:** `SettingsView` builds the same ink capsule toast twice instead of using `Toast`.
- **Press styles differ:** `PressScaleStyle` dims to 0.4 when disabled, and the tab bar's private `TabPressStyle` doesn't.
- **Two screen gutters:** 20 (`l`) in most screens and 28 (`xl`) in onboarding. The reason isn't written down.
- **`Chip` has no XXL preview.**
- **Debug-only exceptions:** `RankDebugBadge` uses a fixed font, black, and a radius of 6. It's Debug-only and can stay.
