import SwiftUI

/// Undo, the free swipes left or the scanning note, and the running "to clear" total.
struct FeedTopBar: View {
    /// Free users see how many swipes are left from here down.
    static let lowSwipes = 5

    @Environment(FeedViewModel.self) private var vm
    let onUndo: () -> Void
    var onOpenPile: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            undoButton
                .frame(maxWidth: .infinity, alignment: .leading)
            status
            Button(action: onOpenPile) {
                counter
                    .animation(DS.Motion.calm, value: vm.deleteChip)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows what's waiting to be cleared")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Free users see how full the pile is, e.g. "12/50 photos", instead of "to clear".
    private var counter: some View {
        let count = vm.pendingItems.count
        let limit = vm.pileLimit
        return ToClearCounter(
            bytes: vm.pendingBytes,
            label: limit.map { "\(count)/\($0) photos" } ?? "to clear",
            accessibilityText: limit.map { "to clear, \(count) of \($0) photos" },
            isLabelEmphasized: vm.isPileFull,
            addedBytes: vm.deleteChip?.bytes,
            addedID: vm.deleteChip?.id
        )
    }

    private var undoButton: some View {
        CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo", action: onUndo)
            .disabled(!vm.canUndo)
    }

    /// The deck has no end, so the middle only speaks up when there's something to say.
    @ViewBuilder
    private var status: some View {
        if let left = vm.swipesLeft, left <= Self.lowSwipes {
            SwipesLeftPill(left: left, nextRefillAt: vm.nextRefillAt, refillAmount: vm.allowanceTunables.refillAmount) {
                vm.presentWall()
            }
            .fixedSize()
            .transition(.opacity)
        } else if let percent = vm.scanningPercent {
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.Palette.brick)
                    .frame(width: 6, height: 6)
                Text("Still scanning · \(percent)%")
            }
            .font(.caption)
            .foregroundStyle(DS.Palette.secondary)
            .fixedSize()
            .transition(.opacity)
        }
    }
}

/// "3 left", or the countdown to the next refill at zero. Opens the wall.
private struct SwipesLeftPill: View {
    let left: Int
    let nextRefillAt: Date?
    let refillAmount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if left == 0, let nextRefillAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Chip(text: "+\(refillAmount) in \(Format.countdown(nextRefillAt.timeIntervalSince(context.date)))", size: .caption)
                        .monospacedDigit()
                }
            } else {
                Chip(text: "\(left) left", size: .caption)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(left == 0 ? "Out of swipes" : "\(left) swipes left")
        .accessibilityHint("Shows when more swipes arrive")
        .accessibilityIdentifier("feed.swipesLeft")
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
