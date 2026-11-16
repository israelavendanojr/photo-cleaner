import SwiftUI

/// Round icon button with a caption underneath, used by the feed's action bar.
struct CircleActionButton: View {
    enum Variant {
        /// Brick icon on tint. Delete.
        case destructive
        /// Ink icon on card with a ring. Later.
        case neutral
        /// A filled ink disc. Keep: the one the eye should land on.
        case primary
    }

    let title: String
    let systemImage: String
    var variant: Variant = .neutral
    var diameter: CGFloat = DS.Control.action
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize * diameter / DS.Control.action, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: diameter, height: diameter)
                    .background(fill, in: Circle())
                    .overlay {
                        if variant == .neutral {
                            Circle().strokeBorder(DS.Palette.outline, lineWidth: DS.Control.ring)
                        }
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.secondary)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch variant {
        case .destructive: DS.Palette.brick
        case .neutral: DS.Palette.ink
        case .primary: DS.Palette.onInk
        }
    }

    private var fill: Color {
        switch variant {
        case .destructive: DS.Palette.brickTint
        case .neutral: DS.Palette.card
        case .primary: DS.Palette.ink
        }
    }
}

/// Subtle press-down scale for icon buttons.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(DS.Motion.calm, value: configuration.isPressed)
    }
}

#Preview {
    HStack(alignment: .top, spacing: DS.Spacing.xl) {
        CircleActionButton(title: "Delete", systemImage: "trash", variant: .destructive) {}
        CircleActionButton(title: "Later", systemImage: "arrow.up", diameter: DS.Control.minorAction) {}
            .padding(.top, DS.Spacing.xs)
        CircleActionButton(title: "Keep", systemImage: "checkmark", variant: .primary) {}
    }
    .padding()
    .paperBackground()
}
