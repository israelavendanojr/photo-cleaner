import SwiftUI

/// Rounded label: the "Best pick" and "Keep" markers, a video's length, swipes left, the feed's focus,
/// and the library card's choices. A trailing symbol (`xmark` on the focus chip) takes the text color, never brick.
struct Chip: View {
    enum Style {
        /// Brick text on tint, e.g. swipes left.
        case brick
        /// Ink text on card. Neutral labels over imagery.
        case plain
        /// White text on frosted dark. Video duration.
        case frosted
        /// One of a row of single-select choices, not chosen: ink text on card inside a `line` outline.
        case option
        /// The chosen one of a row of choices: white text on ink.
        case selected
    }

    let text: String
    var systemImage: String?
    var trailingSystemImage: String?
    var style: Style = .brick
    var size: Font.TextStyle = .subheadline

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(iconColor)
            }
            Text(text)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if style == .frosted {
                Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            } else if style == .option {
                Capsule().fill(background).overlay(Capsule().strokeBorder(DS.Palette.line, lineWidth: 1))
            } else {
                Capsule().fill(background)
            }
        }
    }

    private var foreground: Color {
        switch style {
        case .brick: DS.Palette.brick
        case .plain, .option: DS.Palette.ink
        case .frosted, .selected: .white
        }
    }

    private var iconColor: Color {
        style == .plain ? DS.Palette.brick : foreground
    }

    private var background: Color {
        switch style {
        case .brick: DS.Palette.brickTint
        case .selected: DS.Palette.ink
        default: DS.Palette.card
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Chip(text: "3 left", size: .caption)
        Chip(text: "Best pick", systemImage: "star.fill", style: .plain)
        Chip(text: "Only videos", trailingSystemImage: "xmark", style: .plain, size: .caption)
        HStack {
            Chip(text: "Duplicates", style: .selected)
            Chip(text: "Videos", style: .option)
        }
        Chip(text: "4:12", style: .frosted)
            .padding()
            .background(DS.Palette.ink.opacity(0.6))
    }
    .padding()
    .background(DS.Palette.paper)
}
