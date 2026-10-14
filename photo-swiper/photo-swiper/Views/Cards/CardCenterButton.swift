import SwiftUI

/// An invisible tap target in the middle of a photo or video card that opens it full screen.
///
/// The only way into a preview. Nothing is drawn, so the content stays unobstructed.
/// Drags still reach the card, so swiping works from anywhere.
struct CardCenterButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    /// Side of the invisible square that accepts taps.
    private let hitSize: CGFloat = 160

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
