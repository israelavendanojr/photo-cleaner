import CoreText
import SwiftUI
import UIKit

/// Single source of truth for the app's visual language.
enum DS {
    /// Every colour has a light and a dark value behind the same name, as a colour set in
    /// `Assets.xcassets/Palette`. The values are in DESIGN.md → Color.
    enum Palette {
        /// The app background's colour, under the paper texture (`paperBackground()`).
        static let paper = Color("Palette/paper")
        /// Card surface.
        static let card = Color("Palette/card")
        static let ink = Color("Palette/ink")
        /// Text and icons on an `ink` fill: white in light, near-black in dark, where ink turns pale.
        static let onInk = Color("Palette/onInk")
        static let secondary = Color("Palette/secondary")
        /// Delete, amounts to clear, celebrations. Never anything else. For text, icons and ticks.
        static let brick = Color("Palette/brick")
        /// A brick surface that carries white text: the brick pill, Save. Darker than `brick` in dark
        /// mode, where `brick` is lightened to read as text.
        static let brickFill = Color("Palette/brickFill")
        static let brickTint = Color("Palette/brickTint")
        /// Hairline rules and quiet borders.
        static let line = Color("Palette/line")
        /// The empty part of a tick track, and the ring of an outlined control.
        static let outline = Color("Palette/outline")
        /// Placeholder fill behind images.
        static let muted = Color("Palette/muted")
        static let shadow = Color("Palette/shadow")
        /// The dark wash under a caption on a photo. The same in both appearances: it sits on the
        /// picture, not the paper.
        static let scrim = Color("Palette/scrim")
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
        /// Horizontal inset of the card stack from the screen edge.
        static let cardInset: CGFloat = 28
    }

    enum Radius {
        static let card: CGFloat = 28
        static let inner: CGFloat = 24
        static let tile: CGFloat = 16
        static let thumb: CGFloat = 12
    }

    enum Motion {
        /// Card returning to center after a drag that didn't commit.
        static let snapBack = Animation.spring(duration: 0.45, bounce: 0.14)
        /// Card leaving the stack. Fast out, long soft tail.
        static let flyOut = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.42)
        /// General state changes: counters, stack promotion, undo.
        static let calm = Animation.spring(duration: 0.5, bounce: 0.08)
        /// Screen-level transitions and big reveals.
        static let gentle = Animation.smooth(duration: 0.7)
        /// Moving between onboarding pages. Quick, so the incoming page's own entrance leads.
        static let page = Animation.spring(duration: 0.45, bounce: 0)
        /// The tab bar's selection capsule sliding between tabs. A little bounce so it lands.
        static let tab = Animation.spring(duration: 0.4, bounce: 0.22)
        /// The dashboard's space cleared counting up from zero, once per launch: how long it takes, in how
        /// many steps (each a `calm` numeric-text change), easing out so it slows as it lands.
        /// The hero's progress bar fills alongside, in the same steps.
        static let countUpDuration: Duration = .milliseconds(900)
        static let countUpSteps = 16
        /// The paywall's photos fanning out from a squared pile as it appears.
        static let fan = Animation.spring(duration: 0.7, bounce: 0.25).delay(0.15)
        /// The paywall's selection moving from one plan to the other.
        static let planSelect = Animation.spring(duration: 0.35, bounce: 0.2)
        /// `BristleTicks` filling: the fill sweeps to its new value, and the ticks appear one by one
        /// as it passes them.
        static let tickFill = Animation.easeOut(duration: 0.6)
        /// The Library's rows fading up one after another: the beat between one row and the next, in seconds.
        static let rowStagger = 0.04
        /// The loose stack: a card behind straightening as it comes to the top, and the next one
        /// taking its place at the back.
        static let stackSettle = Animation.spring(duration: 0.5, bounce: 0.12)
    }

    /// The feed's loose stack: the cards waiting behind the top one lie at a slight angle, a little
    /// dimmed, as photos dropped on a table.
    enum Stack {
        /// How many cards show behind the top one.
        static let depth = 2
        /// A waiting card's tilt, either way, in degrees. Each card's own angle comes from its ID.
        static let tilt: ClosedRange<Double> = 3...5
        /// The card right behind the top one sits this far down and across.
        static let nudge: CGFloat = 4
        /// How much darker each step back is.
        static let dimStep = 0.04
    }

    /// The floating tab bar (`PillTabBar`).
    enum TabBar {
        static let padding: CGFloat = 6
        static let itemInset: CGFloat = 22
        static let itemHeight: CGFloat = 48
    }

    /// The feed's round buttons (`CircleActionButton`, `CircleIconButton`).
    enum Control {
        static let action: CGFloat = 68
        static let minorAction: CGFloat = 52
        static let ring: CGFloat = 1.5
        /// A 6pt dot before a label: a card's flag, the scanning note.
        static let dot: CGFloat = 6
    }

    /// The tick motif (`BristleTicks`): upright strokes on a fixed pitch.
    enum Ticks {
        static let stroke: CGFloat = 2
        static let pitch: CGFloat = 5
        /// Heights at the default text size; scale them with `@ScaledMetric`.
        static let meterHeight: CGFloat = 14
        static let heroHeight: CGFloat = 30
        static let rowHeight: CGFloat = 12
        /// How far past its height a filling tick rises when it pops, as a share of the height.
        static let popLift: CGFloat = 0.3
        /// `BristleMark`: its side at the default text size, the brick line it stands on, and how much
        /// of the width the ticks take.
        static let markSide: CGFloat = 22
        static let markLine: CGFloat = 3
        static let markTicksShare: CGFloat = 0.77
    }

    /// The two shadows, each a tight contact line under a short drop, so a surface reads as paper
    /// lying on paper. Dark mode needs them heavier to show at all.
    enum Shadow {
        struct Layer {
            let opacity: Double
            let radius: CGFloat
            let y: CGFloat
        }

        struct Style {
            let contact: Layer
            let drop: Layer
        }

        static func card(dark: Bool) -> Style {
            dark
                ? Style(contact: Layer(opacity: 0.55, radius: 1, y: 1), drop: Layer(opacity: 0.5, radius: 11, y: 12))
                : Style(contact: Layer(opacity: 0.22, radius: 1, y: 1), drop: Layer(opacity: 0.14, radius: 9, y: 10))
        }

        static func soft(dark: Bool, raised: Bool) -> Style {
            dark
                ? Style(contact: Layer(opacity: raised ? 0.5 : 0.4, radius: 1, y: 1), drop: Layer(opacity: 0.35, radius: 7, y: 8))
                : Style(contact: Layer(opacity: raised ? 0.16 : 0.1, radius: 1, y: 1), drop: Layer(opacity: 0.08, radius: 7, y: 8))
        }
    }

    /// The smallest tap target, from the HIG. Small visual marks reach it with a frame or content shape.
    enum Tap {
        static let minimum: CGFloat = 44
    }

    /// The paywall (`PaywallView`).
    enum Paywall {
        /// A hero photo's width at the default text size, and its height as a multiple of that.
        static let heroWidth: CGFloat = 84
        static let heroAspect: CGFloat = 108.0 / 84
        static let heroRadius: CGFloat = 14
        static let iconColumn: CGFloat = 28
        static let benefitMinHeight: CGFloat = 54
        static let planRadius: CGFloat = 18
        static let planInset: CGFloat = 15
        /// The chosen plan's ring, and the round mark in a plan's corner.
        static let selectedRing: CGFloat = 2
        static let mark: CGFloat = 24
    }

    /// A hairline (`Rule`).
    enum Rule {
        static let thickness: CGFloat = 1
    }

    /// A ruled tally row (`TallyRow`): its columns at the default text size (scale them with
    /// `@ScaledMetric`), and its least height, a tap target and a little air.
    enum Tally {
        static let ticksWidth: CGFloat = 84
        static let sizeWidth: CGFloat = 70
        static let minHeight: CGFloat = 45
    }

    /// The full-screen video's trim strip (`TrimStrip`).
    enum Trim {
        /// The strip's height at the default text size; it scales with Dynamic Type.
        static let stripHeight: CGFloat = 48
        /// A handle's visible width. Its touch area reaches out to `Tap.minimum`.
        static let handleWidth: CGFloat = 22
        /// The bar's outer corners: the play button's on the left, the end handle's (or the stills') on the right.
        static let cornerRadius: CGFloat = 6
        /// The frame around what's kept.
        static let frameWidth: CGFloat = 3
        static let playheadWidth: CGFloat = 3
    }

    /// A frosted popup over the full-screen video (`CompressionPopup`): narrow enough to read as a popup on
    /// the largest phones, with the video showing around it.
    enum Popup {
        static let maxWidth: CGFloat = 340
    }
}

// MARK: - Typography

extension DS {
    /// Newsreader, bundled as two variable fonts (upright and italic), at a fixed design size that
    /// still scales with Dynamic Type.
    struct SerifFont: ViewModifier {
        @ScaledMetric private var size: CGFloat
        private let weight: Font.Weight
        private let italic: Bool

        init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, italic: Bool) {
            _size = ScaledMetric(wrappedValue: size, relativeTo: style)
            self.weight = weight
            self.italic = italic
        }

        func body(content: Content) -> some View {
            content.font(Serif.font(size: size, weight: weight, italic: italic))
        }
    }

    /// Builds Newsreader at a size, setting its weight and optical-size axes directly: SwiftUI's
    /// `.weight` doesn't reach a custom variable font's axes.
    enum Serif {
        /// A named instance of each file, to start the descriptor from.
        private static let upright = "Newsreader16pt-Regular"
        private static let slanted = "Newsreader16pt-Italic"
        /// OpenType axis tags, 'wght' and 'opsz'.
        private static let weightAxis = 0x7767_6874
        private static let opticalSizeAxis = 0x6F70_737A
        /// The optical-size axis's range.
        private static let opticalSizes: ClosedRange<CGFloat> = 6...72

        static func font(size: CGFloat, weight: Font.Weight, italic: Bool) -> Font {
            guard let base = UIFont(name: italic ? slanted : upright, size: size) else {
                // The font didn't load: New York, the system serif.
                let font = Font.system(size: size, weight: weight, design: .serif)
                return italic ? font.italic() : font
            }
            let axes: [Int: CGFloat] = [
                weightAxis: axisWeight(weight),
                opticalSizeAxis: min(max(size, opticalSizes.lowerBound), opticalSizes.upperBound),
            ]
            let descriptor = base.fontDescriptor.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
            ])
            return Font(UIFont(descriptor: descriptor, size: size))
        }

        private static func axisWeight(_ weight: Font.Weight) -> CGFloat {
            switch weight {
            case .light: 300
            case .medium: 500
            case .semibold: 600
            case .bold: 700
            default: 400
            }
        }
    }
}

extension View {
    /// Headline and big-number serif. `relativeTo` controls how it scales with Dynamic Type.
    func dsSerif(_ size: CGFloat, relativeTo style: Font.TextStyle = .title, weight: Font.Weight = .regular, italic: Bool = false) -> some View {
        modifier(DS.SerifFont(size: size, relativeTo: style, weight: weight, italic: italic))
    }
}

// MARK: - Shadows

private struct PaperShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let style: (_ dark: Bool) -> DS.Shadow.Style

    func body(content: Content) -> some View {
        let style = style(colorScheme == .dark)
        content
            .shadow(color: DS.Palette.shadow.opacity(style.drop.opacity), radius: style.drop.radius, x: 0, y: style.drop.y)
            .shadow(color: DS.Palette.shadow.opacity(style.contact.opacity), radius: style.contact.radius, x: 0, y: style.contact.y)
    }
}

extension View {
    /// Cards and photos: paper lying on paper.
    func cardShadow() -> some View {
        modifier(PaperShadow { DS.Shadow.card(dark: $0) })
    }

    /// Lighter, for chips, the tab bar and small surfaces. `raised` is a touch firmer, for a
    /// surface that's a choice (the paywall's plan cards).
    func softShadow(raised: Bool = false) -> some View {
        modifier(PaperShadow { DS.Shadow.soft(dark: $0, raised: raised) })
    }
}

// MARK: - Paper

/// The app's background: the paper colour under a creased-paper texture, filling the screen and
/// never stretched out of proportion. It never moves.
struct PaperBackground: View {
    var body: some View {
        DS.Palette.paper
            .overlay {
                Image("Paper")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the paper behind a screen, under the safe areas too.
    func paperBackground() -> some View {
        background { PaperBackground() }
    }
}
