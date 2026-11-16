import SwiftUI

/// Out of free swipes: the paywall, as a sheet over the deck, opened by a refused swipe. Closing it leaves
/// the card where it was; the next refused swipe opens it again. Deleting lives in the pile.
struct SwipeWallView: View {
    @Environment(FeedViewModel.self) private var vm

    var body: some View {
        PaywallView { vm.dismissWall() }
            .interactiveDismissDisabled(vm.isPurchaseBusy)
    }
}

#if DEBUG
#Preview("Out of swipes") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SwipeWallView()
        }
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
}
#endif
