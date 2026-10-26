import SwiftUI

/// Undo, session progress, and the running "to clear" total.
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
            if let left = vm.swipesLeft, left <= Self.lowSwipes {
                SwipesLeftPill(left: left, nextRefillAt: vm.nextRefillAt, refillAmount: vm.allowanceTunables.refillAmount) {
                    vm.presentWall()
                }
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
                .transition(.opacity)
            }
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
