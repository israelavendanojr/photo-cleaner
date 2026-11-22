import SwiftUI

/// Rounded label: the "Best pick" and "Keep" markers, a video's length, the feed's filter pill.
/// A trailing symbol (`chevron.down` on the filter pill) takes the text color, never brick.
struct Chip: View {
    enum Style {
        /// Brick text on tint, for a count tied to clearing.
        case brick
        /// Ink text on card. Neutral labels over imagery.
        case plain
        /// White text on frosted dark. Video duration.
        case frosted
        /// A label lying on a photo: a pale slip with dark text in both appearances, so it reads on
        /// any picture. "Best pick", "Keep".
        case onPhoto
    }

    let text: String
    var systemImage: String?
    var trailingSystemImage: String?
    var style: Style = .brick
    var size: Font.TextStyle = .subheadline
    @Environment(\.colorScheme) private var colorScheme

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
            } else {
                Capsule().fill(background)
            }
        }
    }

    private var foreground: Color {
        switch style {
        case .brick: DS.Palette.brick
        case .plain: DS.Palette.ink
        case .frosted: .white
        case .onPhoto: colorScheme == .dark ? DS.Palette.onInk : DS.Palette.ink
        }
    }

    private var iconColor: Color {
        switch style {
        case .plain: DS.Palette.brick
        // On the pale slip, the brick that reads on a light ground in either appearance.
        case .onPhoto: DS.Palette.brickFill
        case .brick, .frosted: foreground
        }
    }

    private var background: Color {
        switch style {
        case .brick: DS.Palette.brickTint
        case .onPhoto: colorScheme == .dark ? DS.Palette.ink : DS.Palette.card
        case .plain, .frosted: DS.Palette.card
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Chip(text: "12 to clear", size: .caption)
        Chip(text: "Best pick", systemImage: "star.fill", style: .onPhoto)
        Chip(text: "Videos", trailingSystemImage: "chevron.down", style: .plain, size: .caption)
        Chip(text: "4:12", style: .frosted)
            .padding()
            .background(DS.Palette.ink.opacity(0.6))
    }
    .padding()
    .paperBackground()
}
