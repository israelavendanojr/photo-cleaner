import SwiftUI

/// The feed's sort (JUN-125), after the filter pill: "Recommended ⌄", or the sort's name ("Largest ⌄").
/// Tapping opens `FeedSortMenu`, or the paywall while the sort is locked for this plan. FeedTopBar leaves it
/// out when the sort is off. Built on `FeedPill`.
struct FeedSortPill: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isMenuOpen: Bool

    private var asksToUnlock: Bool { vm.featureAccess(.feedSort) == .locked }

    var body: some View {
        FeedPill(title: vm.feedSort.title, fallbackSystemImage: "arrow.up.arrow.down", isOpen: isMenuOpen,
                 accessibilityLabel: "Sorted by \(vm.feedSort.phrase)",
                 accessibilityHint: asksToUnlock ? "Unlock to choose the feed's order" : "Chooses the feed's order",
                 inputLabel: "Sort", identifier: "feed.sort") {
            if asksToUnlock {
                vm.requestUnlock(.feedSort)
            } else {
                withAnimation(DS.Motion.calm) { isMenuOpen.toggle() }
            }
        }
    }
}

/// The orders the feed can deal in, `FeedSort.allCases`, in a `FeedMenu`. Recommended always works; while
/// the sort is locked the others open the paywall. While the index is still working through the library,
/// Largest says so, since it can only sort what's been sized.
struct FeedSortMenu: View {
    @Environment(FeedViewModel.self) private var vm
    @Binding var isOpen: Bool

    var body: some View {
        FeedMenu(identifier: "feed.sort", options: FeedSort.allCases.map(option), isOpen: $isOpen)
    }

    private func option(_ sort: FeedSort) -> FeedMenuOption {
        FeedMenuOption(id: sort.rawValue, title: sort.title,
                       subtitle: sort == .largest && vm.isSizingLibrary ? "Still sizing your library" : nil,
                       isCurrent: vm.feedSort == sort) {
            if sort != .recommended, vm.featureAccess(.feedSort) != .unlocked {
                vm.requestUnlock(.feedSort)
                return
            }
            Haptics.tabChange()
            withAnimation(DS.Motion.calm) { vm.sortFeed(by: sort) }
        }
    }
}

#if DEBUG
#Preview("Menu") {
    FeedSortMenu(isOpen: .constant(true))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
}

#Preview("Menu XXL") {
    FeedSortMenu(isOpen: .constant(true))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
        .dynamicTypeSize(.xxLarge)
}

#Preview("Pill") {
    FeedSortPill(isMenuOpen: .constant(false))
        .padding(DS.Spacing.l)
        .paperBackground()
        .environment(FeedViewModel.mock())
}
#endif
