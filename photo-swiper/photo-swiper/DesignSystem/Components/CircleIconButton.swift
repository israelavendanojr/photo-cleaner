import SwiftUI

/// The outlined 44pt icon button in the top bars, e.g. Undo and Close.
struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Palette.secondary)
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(DS.Palette.line, lineWidth: 1.5) }
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
    .background(DS.Palette.paper)
}
