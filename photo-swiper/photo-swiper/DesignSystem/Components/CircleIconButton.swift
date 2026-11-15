import SwiftUI

/// The outlined 44pt icon button in the top bars, e.g. Undo and Close.
struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: DS.Tap.minimum, height: DS.Tap.minimum)
                .background(DS.Palette.card, in: Circle())
                .overlay { Circle().strokeBorder(DS.Palette.outline, lineWidth: DS.Control.ring) }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    HStack {
        CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {}
        CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo") {}
    }
    .padding()
    .paperBackground()
}
