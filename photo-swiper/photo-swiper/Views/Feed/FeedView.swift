import SwiftUI

/// The main screen: top bar and the card stack.
struct FeedView: View {
    @Environment(FeedViewModel.self) private var vm
    var onOpenPile: () -> Void = {}
    /// The unlock, offered from the full-pile notice.
    @State private var isUnlockPresented = false

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
        .sheet(isPresented: Bindable(vm).isWallPresented) {
            SwipeWallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .sheet(isPresented: $isUnlockPresented) {
            UnlockSheet(
                title: "No limit on the pile",
                subtitle: "Free piles hold \(FeedViewModel.freePileCap) photos. Unlock to keep deleting without stopping to clear."
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(DS.Palette.paper)
            .presentationCornerRadius(DS.Radius.card)
        }
        .alert("Your pile is full", isPresented: Bindable(vm).isPileFullNoticePresented) {
            Button("Review pile", action: onOpenPile)
            Button("Unlock") { isUnlockPresented = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Free piles hold \(FeedViewModel.freePileCap) photos. Clear them to keep deleting, or unlock for no limit.")
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
