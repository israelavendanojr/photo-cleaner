import SwiftUI

/// The main screen: handle, top bar, and the card stack.
struct FeedView: View {
    @Environment(FeedViewModel.self) private var vm
    let onOpenOverview: () -> Void
    var onOpenPile: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            OverviewHandle(onOpen: onOpenOverview)
            FeedTopBar(onUndo: {
                withAnimation(DS.Motion.calm) { vm.undo() }
            }, onOpenPile: onOpenPile)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.m)
            CardStackView()
        }
        .background(DS.Palette.paper)
    }
}

#Preview("Feed") {
    FeedView(onOpenOverview: {})
        .environment(FeedViewModel.mock())
}

#Preview("Similar") {
    FeedView(onOpenOverview: {})
        .environment(FeedViewModel.mock(startingAt: .similar))
}
