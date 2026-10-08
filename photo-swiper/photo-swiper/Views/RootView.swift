import SwiftUI

/// Switches between the feed, the end of a session, and the caught-up state.
struct RootView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var isOverviewPresented = false

    var body: some View {
        ZStack {
            DS.Palette.paper.ignoresSafeArea()
            switch vm.phase {
            case .loading:
                ProgressView()
                    .tint(DS.Palette.secondary)
            case .noAccess:
                LibraryAccessView()
                    .transition(.opacity)
            case .feed:
                FeedView { isOverviewPresented = true }
                    .transition(.opacity)
            case .endOfSession, .celebrated:
                EndOfSessionView()
                    .transition(.opacity)
            case .caughtUp:
                CaughtUpView { isOverviewPresented = true }
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.gentle, value: vm.phase)
        .sheet(isPresented: $isOverviewPresented) {
            OverviewSheet()
        }
        .task {
            await vm.start()
            #if DEBUG
            // `-showOverview YES` opens the sheet at launch, for screenshots.
            if UserDefaults.standard.bool(forKey: "showOverview") { isOverviewPresented = true }
            #endif
        }
    }
}

#Preview {
    RootView()
        .environment(FeedViewModel.mock())
}
