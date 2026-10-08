import SwiftUI

/// Full-height rounded button used for primary and secondary actions.
struct PillButtonStyle: ButtonStyle {
    enum Variant { case ink, brick, outline, ghost }

    let variant: Variant
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, DS.Spacing.l)
            .background(background, in: Capsule())
            .overlay {
                if variant == .outline {
                    Capsule().strokeBorder(DS.Palette.line, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(DS.Motion.calm, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .ink, .brick: .white
        case .outline: DS.Palette.ink
        case .ghost: DS.Palette.secondary
        }
    }

    private var background: Color {
        switch variant {
        case .ink: DS.Palette.ink
        case .brick: DS.Palette.brick
        case .outline, .ghost: .clear
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ variant: PillButtonStyle.Variant) -> PillButtonStyle {
        PillButtonStyle(variant: variant)
    }
}

#Preview {
    VStack(spacing: 12) {
        Button("Delete 37 Photos") {}.buttonStyle(.pill(.brick))
        Button("Start another session") {}.buttonStyle(.pill(.ink))
        HStack(spacing: 12) {
            Button("Keep going") {}.buttonStyle(.pill(.outline))
            Button("Done for now") {}.buttonStyle(.pill(.ghost))
        }
        Button("Disabled") {}.buttonStyle(.pill(.brick)).disabled(true)
    }
    .padding(26)
    .background(DS.Palette.paper)
}
