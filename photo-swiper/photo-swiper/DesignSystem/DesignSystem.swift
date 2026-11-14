import SwiftUI

/// Single source of truth for the app's visual language.
enum DS {
    enum Palette {
        /// Warm paper white app background.
        static let paper = Color(hex: 0xFAF7F2)
        /// Card surface.
        static let card = Color(hex: 0xFFFDF9)
        static let ink = Color(hex: 0x1F1B18)
        static let secondary = Color(hex: 0x8A817A)
        /// Delete, amounts to clear, celebrations. Never anything else.
        static let brick = Color(hex: 0xC24A3A)
        static let brickTint = Color(hex: 0xF5E4DF)
        /// Hairlines, empty progress tracks, outlined buttons.
        static let line = Color(hex: 0xE9E3DB)
        /// Placeholder fill behind images.
        static let muted = Color(hex: 0xEEE8E0)
        static let shadow = Color(hex: 0x4A382B)
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
        static let cardInset: CGFloat = 14
    }

    enum Radius {
        static let card: CGFloat = 32
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
    }

    /// The smallest tap target, from the HIG. Small visual marks reach it with a frame or content shape.
    enum Tap {
        static let minimum: CGFloat = 44
    }

    /// The dashboard's library list: the icon column, wide enough for a badged symbol, at the default text
    /// size; scale it with `@ScaledMetric`.
    enum LibraryList {
        static let iconWidth: CGFloat = 28
    }

    /// The dashboard's bin (`BinCard`): its trash circle, the same size as the pile screen's, at the default
    /// text size; scale it with `@ScaledMetric`.
    enum Bin {
        static let iconDiameter: CGFloat = 52
    }

    /// The full-screen video's trim strip (`TrimStrip`).
    enum Trim {
        /// The strip's height at the default text size; it scales with Dynamic Type.
        static let stripHeight: CGFloat = 48
        /// A handle's visible width. Its touch area reaches out to `Tap.minimum`.
        static let handleWidth: CGFloat = 18
        /// The frame around what's kept.
        static let frameWidth: CGFloat = 3
        static let playheadWidth: CGFloat = 3
    }

    /// The dashboard hero's progress through the whole library: a thicker `ProgressLine` than the feed's,
    /// since it's the card's one visual.
    enum Progress {
        static let heroHeight: CGFloat = 6
    }
}

// MARK: - Typography

extension DS {
    /// New York at a fixed design size that still scales with Dynamic Type.
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
            let font = Font.system(size: size, weight: weight, design: .serif)
            content.font(italic ? font.italic() : font)
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

extension View {
    /// Soft, warm lift for cards.
    func cardShadow() -> some View {
        shadow(color: DS.Palette.shadow.opacity(0.14), radius: 22, x: 0, y: 16)
            .shadow(color: DS.Palette.shadow.opacity(0.05), radius: 3, x: 0, y: 2)
    }

    /// Lighter lift for chips and grouped rows.
    func softShadow() -> some View {
        shadow(color: DS.Palette.shadow.opacity(0.12), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Color

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
