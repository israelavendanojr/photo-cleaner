import SwiftUI

/// Round icon button with a caption underneath, used by the feed's action bar.
struct CircleActionButton: View {
    enum Variant {
        /// Brick icon on tint. Delete.
        case destructive
        /// Ink icon on card with a hairline. Keep, Later.
        case neutral
    }

    let title: String
    let systemImage: String
    var variant: Variant = .neutral
    var diameter: CGFloat = 68
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize * diameter / 68, weight: .medium))
                    .foregroundStyle(variant == .destructive ? DS.Palette.brick : DS.Palette.ink)
                    .frame(width: diameter, height: diameter)
                    .background(variant == .destructive ? DS.Palette.brickTint : DS.Palette.card, in: Circle())
                    .overlay {
                        if variant == .neutral {
                            Circle().strokeBorder(DS.Palette.line, lineWidth: 1.5)
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
    HStack(alignment: .top, spacing: 28) {
        CircleActionButton(title: "Delete", systemImage: "trash", variant: .destructive) {}
        CircleActionButton(title: "Later", systemImage: "arrow.up", diameter: 52) {}
            .padding(.top, 8)
        CircleActionButton(title: "Keep", systemImage: "checkmark") {}
    }
    .padding()
    .background(DS.Palette.paper)
}
