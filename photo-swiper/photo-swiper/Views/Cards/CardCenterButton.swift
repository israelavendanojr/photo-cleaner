import SwiftUI

/// The frosted circle in the middle of a photo or video card that opens it full screen.
///
/// The only way into a preview, so the rest of the card stays free for swiping.
struct CardCenterButton: View {
    let systemImage: String
    let accessibilityLabel: String
    /// Nudges symbols that look off-center, like the play triangle.
    var iconOffset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .offset(x: iconOffset)
                .frame(width: 80, height: 80)
                .background {
                    Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}
