import SwiftUI

/// Undo, session progress, and the running "to clear" total.
struct FeedTopBar: View {
    @Environment(FeedViewModel.self) private var vm
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            undoButton
                .frame(maxWidth: .infinity, alignment: .leading)
            progress
            ToClearCounter(bytes: vm.pendingBytes, addedBytes: vm.deleteChip?.bytes, addedID: vm.deleteChip?.id)
                .animation(DS.Motion.calm, value: vm.deleteChip)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Palette.secondary)
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(DS.Palette.line, lineWidth: 1.5) }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!vm.canUndo)
        .accessibilityLabel("Undo")
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Text("\(vm.position) of \(vm.cards.count)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.secondary)
                .contentTransition(.numericText(value: Double(vm.position)))
            ProgressLine(value: vm.sessionProgress)
                .frame(width: 96)
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
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeedTopBar(onUndo: {})
        .environment(FeedViewModel.mock())
        .padding(20)
        .background(DS.Palette.paper)
}
