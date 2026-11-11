import SwiftUI

/// The main screen: top bar and the card stack.
struct FeedView: View {
    @Environment(FeedViewModel.self) private var vm
    var onOpenPile: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            FeedTopBar(onUndo: {
                withAnimation(DS.Motion.calm) { vm.undo() }
            }, onOpenPile: onOpenPile)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.m)
            CardStackView()
        }
        .background(DS.Palette.paper)
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
}

#if DEBUG
#Preview("Feed") {
    FeedView()
        .environment(FeedViewModel.mock())
}

#Preview("Similar") {
    FeedView()
        .environment(FeedViewModel.mock(startingAt: .similar))
}
#endif
