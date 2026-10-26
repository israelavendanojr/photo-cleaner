import SwiftUI

/// Undo, session progress, and the running "to clear" total.
struct FeedTopBar: View {
    @Environment(FeedViewModel.self) private var vm
    let onUndo: () -> Void
    var onOpenPile: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            undoButton
                .frame(maxWidth: .infinity, alignment: .leading)
            progress
            Button(action: onOpenPile) {
                ToClearCounter(bytes: vm.pendingBytes, addedBytes: vm.deleteChip?.bytes, addedID: vm.deleteChip?.id)
                    .animation(DS.Motion.calm, value: vm.deleteChip)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows what's waiting to be cleared")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var undoButton: some View {
        CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo", action: onUndo)
            .disabled(!vm.canUndo)
    }

    private var progress: some View {
        DeckProgress(position: vm.photosReviewed, total: vm.photoTotal, value: vm.sessionProgress) {
            if let percent = vm.scanningPercent {
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Palette.brick)
                        .frame(width: 6, height: 6)
                    Text("Still scanning · \(percent)%")
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.secondary)
                .transition(.opacity)
            }
        }
    }
}

#if DEBUG
#Preview {
    FeedTopBar(onUndo: {})
        .environment(FeedViewModel.mock())
        .padding(20)
        .background(DS.Palette.paper)
}
#endif
