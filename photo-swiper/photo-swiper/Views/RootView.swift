import SwiftUI

/// Switches between onboarding, the tabs (feed and library), the end of a session, and the access states.
struct RootView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var tab: AppTab = .feed
    @State private var isPilePresented = false
    /// The feed is about to replace onboarding, so its first deck deals in.
    @State private var dealsInDeck = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Carries the freed figure from the celebration to the rest screen.
    @Namespace private var freedFigure

    var body: some View {
        ZStack {
            DS.Palette.paper.ignoresSafeArea()
            switch vm.phase {
            case .loading:
                DelayedProgressView()
            case .onboarding:
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .onAppear { dealsInDeck = true }
            case .noAccess:
                LibraryAccessView()
                    .transition(.opacity)
            case .feed, .resting, .caughtUp:
                tabs
                    .transition(.opacity)
            case .paywall:
                PaywallView()
                    .transition(paywallTransition)
                    .onAppear { dealsInDeck = true }
            case .endOfSession, .celebrated:
                EndOfSessionView()
                    .transition(.opacity)
            }
        }
        .environment(\.dealsInFirstDeck, dealsInDeck)
        .environment(\.freedFigureNamespace, reduceMotion ? nil : freedFigure)
        .animation(DS.Motion.gentle, value: vm.phase)
        .onChange(of: vm.phase) { old, new in
            // Only the feed that replaces onboarding or the paywall deals in.
            let dealers: [FeedViewModel.Phase] = [.onboarding, .paywall]
            if !dealers.contains(old), !dealers.contains(new) { dealsInDeck = false }
            // A session started from the end, rest, or paywall screen opens on the feed.
            if new == .feed, [.endOfSession, .celebrated, .resting, .caughtUp, .paywall].contains(old) { tab = .feed }
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

    /// The card rises in on its own; once unlocked it lifts away as the next deck deals in.
    private var paywallTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity,
            removal: .offset(y: -60).combined(with: .scale(scale: 1.02)).combined(with: .opacity)
        )
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
        switch vm.phase {
        case .resting:
            RestView(onOpenPile: { isPilePresented = true }, onSeeLibrary: { tab = .library })
                .transition(.opacity)
        case .caughtUp:
            CaughtUpView()
                .transition(.opacity)
        default:
            FeedView(onOpenPile: { isPilePresented = true })
                .transition(.opacity)
        }
    }
}

extension EnvironmentValues {
    /// Shared by the end screen and the rest screen so the freed figure moves between them.
    /// Nil with Reduce Motion, which crossfades instead.
    @Entry var freedFigureNamespace: Namespace.ID?
}

extension View {
    /// The big freed number, matched across screens when `namespace` is set.
    @ViewBuilder
    func freedFigure(in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "freedFigure", in: namespace)
        } else {
            self
        }
    }
}

/// A spinner that only shows if loading takes a moment, so a quick launch into onboarding or
/// the feed doesn't flash it.
private struct DelayedProgressView: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .tint(DS.Palette.secondary)
            .opacity(isShown ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeIn(duration: 0.2)) { isShown = true }
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

#if DEBUG
#Preview {
    RootView()
        .environment(FeedViewModel.mock())
}
#endif
