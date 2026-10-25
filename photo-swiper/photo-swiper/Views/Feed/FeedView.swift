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
