import SwiftUI

/// The feed's filter (JUN-87), between Undo and the counter: "Everything ⌄", or the focus's name
/// ("Videos ⌄"). Tapping opens `FeedFilterMenu`. While the filter is locked for this plan and nothing is
/// focused, it opens the paywall instead. Focused (a free Top Categories row can focus a free user's feed),
/// the menu opens whatever the plan, so Everything is always a way back.
/// FeedTopBar leaves it out when the filter is off and nothing is focused. Built on `FeedPill`.
struct FeedFilterPill: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isMenuOpen: Bool

    private var title: String { vm.feedFocus?.title ?? "Everything" }
    /// Tapping asks to unlock instead of opening the menu.
    private var asksToUnlock: Bool { vm.featureAccess(.feedFilters) == .locked && vm.feedFocus == nil }

    var body: some View {
        FeedPill(title: title, fallbackSystemImage: "line.3.horizontal.decrease", isOpen: isMenuOpen,
                 accessibilityLabel: "Showing \(vm.feedFocus?.phrase ?? "everything")",
                 accessibilityHint: asksToUnlock ? "Unlock to choose what the feed shows" : "Chooses what the feed shows",
                 inputLabel: "Filter", identifier: "feed.filter") {
            if asksToUnlock {
                vm.requestUnlock(.feedFilters)
            } else {
                withAnimation(DS.Motion.calm) { isMenuOpen.toggle() }
            }
        }
    }
}

/// What the feed can show: Everything, then each `FocusTarget` in `FocusTarget.filterOrder`, names only, in a
/// `FeedMenu`. Choosing Everything always works, so nobody is stuck in a focus. While the filter is locked the
/// other rows open the paywall; while it's off only Everything is offered.
struct FeedFilterMenu: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isOpen: Bool

    private var access: FeatureAccess { vm.featureAccess(.feedFilters) }
    private var targets: [FocusTarget?] { [nil] + (access.isVisible ? FocusTarget.filterOrder : []) }

    var body: some View {
        FeedMenu(identifier: "feed.filter", options: targets.map(option), isOpen: $isOpen)
    }

    private func option(_ target: FocusTarget?) -> FeedMenuOption {
        FeedMenuOption(id: target?.identifier ?? "everything", title: target?.title ?? "Everything",
                       isCurrent: vm.feedFocus == target) {
            if target != nil, access != .unlocked {
                vm.requestUnlock(.feedFilters)
                return
            }
            Haptics.tabChange()
            withAnimation(DS.Motion.calm) { vm.focusFeed(on: target) }
        }
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
