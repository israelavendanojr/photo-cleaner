import SwiftUI

/// Undo, the filter pill (unless the filter is off for this plan and nothing is focused), the sort pill
/// (unless the sort is off for this plan), and the running "to clear" total.
/// For a free user, the pile's meter runs under them: how full the free pile is, in ticks.
struct FeedTopBar: View {
    @Environment(FeedViewModel.self) private var vm
    let onUndo: () -> Void
    var onOpenPile: () -> Void = {}
    /// The open menu, filter or sort, which FeedView draws over the deck. Only one is open at a time.
    @Binding var openMenu: FeedMenuKind?

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            HStack(alignment: .center, spacing: DS.Spacing.xs) {
                undoButton
                // Beside Undo, and never wider than the bar: every tab shares RootView's ZStack, so
                // a wider feed would widen the Library tab too.
                // Off hides it, unless the feed is focused: then it shows what's focused, and the way back.
                if vm.featureAccess(.feedFilters).isVisible || vm.feedFocus != nil {
                    FeedFilterPill(isMenuOpen: isOpen(.filter))
                        .layoutPriority(-1)
                }
                if vm.featureAccess(.feedSort).isVisible {
                    // Below the filter: where both names don't fit, the sort gives way to its icon first.
                    FeedSortPill(isMenuOpen: isOpen(.sort))
                        .layoutPriority(-2)
                }
                Spacer(minLength: 0)
                Button(action: onOpenPile) {
                    counter
                        .animation(DS.Motion.calm, value: vm.deleteChip)
                        .frame(minHeight: DS.Tap.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows what's waiting to be cleared")
            }
            if let limit = vm.pileLimitBytes {
                FreePileMeter(counted: vm.pileCountedBytes, limit: limit, waiting: vm.pendingItems.count)
            }
        }
    }

    /// Free users see how full the pile is, e.g. "320 MB" over "of 1 GB", instead of "to clear". The
    /// limit counts only deletes, so that's what they see; otherwise it's the bin, edits included.
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

    /// Opening one menu closes the other.
    private func isOpen(_ menu: FeedMenuKind) -> Binding<Bool> {
        Binding(get: { openMenu == menu }, set: { openMenu = $0 ? menu : (openMenu == menu ? nil : openMenu) })
    }

    private var undoButton: some View {
        CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo", action: onUndo)
            .disabled(!vm.canUndo)
    }
}

/// How full the free pile is, as brick ticks, with what's waiting in it. New ticks pop as a photo
/// is piled. Only free users have a limit, so only they see it.
private struct FreePileMeter: View {
    let counted: Int64
    let limit: Int64
    let waiting: Int

    private var fill: Double { min(1, Double(counted) / Double(max(limit, 1))) }
    private var waitingText: String { "\(Format.count(waiting)) \(waiting == 1 ? "photo" : "photos") waiting" }

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            BristleTicks(value: fill, tint: DS.Palette.brick, popsNew: true)
            HStack(alignment: .firstTextBaseline) {
                Text("Free pile")
                Spacer(minLength: DS.Spacing.xs)
                Text(waitingText)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(waiting)))
            }
            .font(.caption)
            .foregroundStyle(DS.Palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Free pile, \(Format.percent(fill)) full, \(waitingText)")
        .accessibilityIdentifier("feed.pileMeter")
    }
}

#if DEBUG
#Preview {
    FeedTopBar(onUndo: {}, openMenu: .constant(nil))
        .environment(FeedViewModel.mock())
        .padding(DS.Spacing.l)
        .paperBackground()
}
#endif
