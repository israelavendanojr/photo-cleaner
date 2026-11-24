import SwiftUI

/// A round 44pt frosted button over media: the full-screen video's close, volume and compression, the
/// compression popup's close, and the Share button on photo and video cards. Active (a compression level
/// set) fills it brick, as trimming turns the strip brick: space to clear. Busy swaps the icon for a
/// spinner and stays tappable, so the same tap can cancel what it started.
struct FrostedIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isActive = false
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: DS.Tap.minimum, height: DS.Tap.minimum)
            .background(isActive ? AnyShapeStyle(DS.Palette.brickFill) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: DS.Spacing.m) {
        FrostedIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {}
        FrostedIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Cancel sharing", isBusy: true) {}
        FrostedIconButton(systemImage: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Compress", isActive: true) {}
    }
    .padding(DS.Spacing.xl)
    .background(DS.Palette.scrim)
}

#Preview("Large text") {
    FrostedIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {}
        .padding(DS.Spacing.xl)
        .background(DS.Palette.scrim)
        .dynamicTypeSize(.xxLarge)
}
#endif
