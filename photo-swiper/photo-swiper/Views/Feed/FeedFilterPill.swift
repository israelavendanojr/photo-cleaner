import SwiftUI

/// The feed's filter (JUN-87), between Undo and the counter: "Everything ⌄", or the focus's name
/// ("Videos ⌄"). Tapping opens `FeedFilterMenu`. While the filter is locked for this plan and nothing is
/// focused, it opens the paywall instead. Focused (a free Top Categories row can focus a free user's feed),
/// the menu opens whatever the plan, so Everything is always a way back.
/// FeedTopBar leaves it out when the filter is off and nothing is focused.
struct FeedFilterPill: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isMenuOpen: Bool

    private var title: String { vm.feedFocus?.title ?? "Everything" }
    /// Tapping asks to unlock instead of opening the menu.
    private var asksToUnlock: Bool { vm.featureAccess(.feedFilters) == .locked && vm.feedFocus == nil }

    var body: some View {
        Button {
            if asksToUnlock {
                vm.requestUnlock(.feedFilters)
            } else {
                withAnimation(DS.Motion.calm) { isMenuOpen.toggle() }
            }
        } label: {
            // The counter keeps its room. Where the name doesn't fit (accessibility sizes), a filter icon stands
            // in for it; VoiceOver and Voice Control still get the name.
            ViewThatFits(in: .horizontal) {
                Chip(text: title, trailingSystemImage: "chevron.down", style: .plain, size: .caption)
                    .lineLimit(1)
                // The trailing symbol takes the text color (ink); a leading one would be brick.
                Chip(text: "", trailingSystemImage: "line.3.horizontal.decrease", style: .plain, size: .caption)
            }
            .softShadow()
            .frame(minHeight: DS.Tap.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Showing \(vm.feedFocus?.phrase ?? "everything")")
        .accessibilityHint(asksToUnlock ? "Unlock to choose what the feed shows" : "Chooses what the feed shows")
        .accessibilityValue(isMenuOpen ? "Open" : "")
        .accessibilityInputLabels([title, "Filter"])
        .accessibilityIdentifier("feed.filter")
    }
}

/// What the feed can show: Everything, then each `FocusTarget` in `FocusTarget.filterOrder`, names only.
/// A paper card under the top bar, over the deck; it scrolls when it doesn't fit (accessibility sizes).
/// Choosing Everything always works, so nobody is stuck in a focus. While the filter is locked the other
/// rows open the paywall; while it's off only Everything is offered. FeedView closes it on a tap outside,
/// and VoiceOver's escape closes it too. VoiceOver starts on the current choice.
struct FeedFilterMenu: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isOpen: Bool
    @AccessibilityFocusState private var focusedRow: String?

    private var access: FeatureAccess { vm.featureAccess(.feedFilters) }
    private var targets: [FocusTarget] { access.isVisible ? FocusTarget.filterOrder : [] }

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: DS.Popup.maxWidth)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .softShadow(raised: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .accessibilityIdentifier("feed.filter.menu")
        .onAppear { focusedRow = vm.feedFocus?.identifier ?? "everything" }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(nil)
            ForEach(targets, id: \.self) { target in
                Rule()
                row(target)
            }
        }
    }

    private func row(_ target: FocusTarget?) -> some View {
        let isCurrent = vm.feedFocus == target
        let identifier = target?.identifier ?? "everything"
        return Button {
            close()
            if target != nil, access != .unlocked {
                vm.requestUnlock(.feedFilters)
                return
            }
            Haptics.tabChange()
            withAnimation(DS.Motion.calm) { vm.focusFeed(on: target) }
        } label: {
            HStack(spacing: DS.Spacing.s) {
                Text(target?.title ?? "Everything")
                    .foregroundStyle(DS.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minHeight: DS.Tap.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityFocused($focusedRow, equals: identifier)
        .accessibilityIdentifier("feed.filter.option.\(identifier)")
    }

    private func close() {
        withAnimation(DS.Motion.calm) { isOpen = false }
    }
}

#if DEBUG
#Preview("Menu") {
    FeedFilterMenu(isOpen: .constant(true))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
}

#Preview("Menu XXL") {
    FeedFilterMenu(isOpen: .constant(true))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
        .dynamicTypeSize(.xxLarge)
}

#Preview("Pill") {
    FeedFilterPill(isMenuOpen: .constant(false))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
}
#endif
