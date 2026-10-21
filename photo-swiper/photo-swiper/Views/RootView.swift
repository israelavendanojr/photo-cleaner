import SwiftUI

/// Switches between onboarding, the tabs (feed and library), the end of a session, and the access states.
struct RootView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var tab: AppTab = .feed
    @State private var isPilePresented = false

    var body: some View {
        ZStack {
            DS.Palette.paper.ignoresSafeArea()
            switch vm.phase {
            case .loading:
                ProgressView()
                    .tint(DS.Palette.secondary)
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .noAccess:
                LibraryAccessView()
                    .transition(.opacity)
            case .feed, .caughtUp:
                tabs
                    .transition(.opacity)
            case .endOfSession, .celebrated:
                EndOfSessionView()
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.gentle, value: vm.phase)
        .onChange(of: vm.phase) { old, new in
            // A session started from the end screen opens on the feed.
            if new == .feed, old == .endOfSession || old == .celebrated { tab = .feed }
        }
        .sheet(isPresented: $isPilePresented) {
            PendingPileView(showsDone: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .task {
            await vm.start()
            #if DEBUG
            // `-showLibrary YES` opens on the Library tab, for screenshots.
            if UserDefaults.standard.bool(forKey: "showLibrary") { tab = .library }
            // `-showPile YES` opens the pending pile at launch.
            if UserDefaults.standard.bool(forKey: "showPile") { isPilePresented = true }
            #endif
        }
    }

    /// Both tabs stay mounted so the deck keeps its place while the library is up.
    private var tabs: some View {
        ZStack {
            feedTab
                .tabVisibility(tab == .feed)
            LibraryView()
                .tabVisibility(tab == .library)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PillTabBar(items: AppTab.allCases.map(\.tabItem), selection: $tab)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.xxs)
        }
    }

    @ViewBuilder
    private var feedTab: some View {
        if vm.phase == .caughtUp {
            CaughtUpView()
                .transition(.opacity)
        } else {
            FeedView(onOpenPile: { isPilePresented = true })
                .transition(.opacity)
        }
    }
}

private extension View {
    /// Crossfades a tab in or out without unmounting it.
    func tabVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: isVisible)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

#Preview {
    RootView()
        .environment(FeedViewModel.mock())
}
