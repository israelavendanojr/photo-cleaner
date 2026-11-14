import SwiftUI

/// Undo, the free swipes left, the feed's focus or the scanning note, and the running "to clear" total.
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
            // One line when it fits; otherwise it wraps. Never wider than the bar: every tab shares
            // RootView's ZStack, so a wider feed would widen the Library tab too.
            ViewThatFits(in: .horizontal) {
                status.fixedSize()
                status.fixedSize(horizontal: false, vertical: true)
            }
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

    /// Free users see how full the pile is, e.g. "320 MB" over "of 1 GB", instead of "to clear". The
    /// limit counts only deletes, so that's what they see; otherwise it's the bin, trims included.
    private var counter: some View {
        let limit = vm.pileLimitBytes.map(Format.limit)
        return ToClearCounter(
            bytes: limit == nil ? vm.binBytes : vm.pendingBytes,
            label: limit.map { "of \($0)" } ?? "to clear",
            accessibilityText: limit.map { "to clear, of \($0) free pile" },

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
            SwipesLeftPill(left: left) {
                vm.presentWall()
            }
            .transition(.opacity)
        } else if let focus = vm.feedFocus {
            FeedFocusChip(focus: focus)
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

/// "3 left", down to "0 left". Opens the wall.
private struct SwipesLeftPill: View {
    let left: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Chip(text: "\(left) left", size: .caption)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("\(left) swipes left")
        .accessibilityHint("Shows when more swipes arrive")
        .accessibilityIdentifier("feed.swipesLeft")
    }
}

/// "Only videos ×": the feed is focused from the dashboard. Tapping shows everything again.
struct FeedFocusChip: View {
    @Environment(FeedViewModel.self) private var vm
    let focus: FocusTarget

    var body: some View {
        Button {
            withAnimation(DS.Motion.calm) { vm.focusFeed(on: nil) }
        } label: {
            Chip(text: focus.focusTitle, trailingSystemImage: "xmark", style: .plain, size: .caption)
                .softShadow()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Showing \(focus.phrase)")
        .accessibilityHint("Shows everything again")
        .accessibilityIdentifier("feed.focus")
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
