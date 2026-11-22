import SwiftUI

/// The main screen: top bar and the card stack.
struct FeedView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenPile: () -> Void = {}
    /// The filter's menu is open: it sits over the deck, swipes are off, and a tap outside closes it.
    @State private var isFilterOpen = false
    /// Where the deck starts, so the menu opens just under the top bar.
    @State private var topBarHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                FeedTopBar(onUndo: {
                    withAnimation(DS.Motion.calm) { vm.undo() }
                }, onOpenPile: onOpenPile, isFilterOpen: $isFilterOpen)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.top, DS.Spacing.xxs)
                    .padding(.bottom, DS.Spacing.l)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                CardStackView()
                    .overlay(alignment: .top) { trimToast }
                    .allowsHitTesting(!isFilterOpen)
                    .accessibilityHidden(isFilterOpen)
            }
            if isFilterOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(DS.Motion.calm) { isFilterOpen = false } }
                    .accessibilityHidden(true)
                FeedFilterMenu(isOpen: $isFilterOpen)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.top, max(0, topBarHeight - DS.Spacing.s))
                    .padding(.bottom, DS.Spacing.l)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
        }
        .animation(DS.Motion.calm, value: vm.trimToast)
        // Free users clear the pile to go on; the unlock is offered after the delete instead.
        .alert("Your pile is full", isPresented: Binding(get: { vm.isPileFullNoticePresented }, set: { if !$0 { vm.dismissPileFullNotice() } })) {
            Button("Review pile", action: onOpenPile)
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Free piles hold up to \(Format.limit(vm.freeBinBytes)). Delete what's in it to keep clearing.")
        }

        .task(id: vm.nextRefillAt) {
            // Credits the refill the moment it's due, so the countdown and the deck move on by themselves.
            guard let next = vm.nextRefillAt else { return }
            try? await Task.sleep(for: .seconds(max(0.5, next.timeIntervalSinceNow)))
            vm.refreshAllowance()
        }
    }

    /// "Edit queued · saves ~335 MB · Undo" ("Flatten queued" for a Live Photo), over the top of the deck after
    /// an edit from full screen.
    @ViewBuilder private var trimToast: some View {
        if let toast = vm.trimToast {
            Toast(text: "\(toast.isFlatten ? "Flatten" : "Edit") queued · saves ~\(Format.size(toast.savedBytes))", actionTitle: "Undo") {
                withAnimation(DS.Motion.calm) { vm.undo() }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xs)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .id(toast.id)
            .accessibilityIdentifier("feed.trimToast")
        }
    }
}

#if DEBUG
#Preview("Feed") {
    FeedView()
        .environment(FeedViewModel.mock())
        .paperBackground()
}

#Preview("Dark") {
    FeedView()
        .environment(FeedViewModel.mock())
        .paperBackground()
        .preferredColorScheme(.dark)
}

#Preview("XXL") {
    FeedView()
        .environment(FeedViewModel.mock())
        .paperBackground()
        .dynamicTypeSize(.xxLarge)
}

#Preview("Similar") {
    FeedView()
        .environment(FeedViewModel.mock(startingAt: .similar))
        .paperBackground()
}
#endif
