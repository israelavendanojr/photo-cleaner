import SwiftUI

/// Rounded label used for flags, card kinds, and the "Best pick" badge.
struct Chip: View {
    enum Style {
        /// Brick text on tint. Flags and card kinds.
        case brick
        /// Ink text on card. Neutral labels over imagery.
        case plain
        /// White text on frosted dark. Video duration.
        case frosted
    }

    let text: String
    var systemImage: String?
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
        }
    }

    private var iconColor: Color {
        style == .plain ? DS.Palette.brick : foreground
    }

    private var background: Color {
        style == .brick ? DS.Palette.brickTint : DS.Palette.card
    }
}

#Preview {
    VStack(spacing: 16) {
        Chip(text: "Possibly blurry", systemImage: "exclamationmark.circle")
        Chip(text: "6 similar shots")
        Chip(text: "Best pick", systemImage: "star.fill", style: .plain)
        Chip(text: "Video · 4:12", style: .frosted)
            .padding()
            .background(DS.Palette.ink.opacity(0.6))
    }
    .padding()
    .background(DS.Palette.paper)
}
