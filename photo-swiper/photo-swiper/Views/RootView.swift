import StoreKit
import SwiftUI

/// Switches between onboarding, the tabs (feed, library, and Admin in Developer mode), and the access states.
struct RootView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var tab: AppTab = .feed
    @State private var isPilePresented = false
    /// The unlock offered after a free user's delete.
    @State private var isUpsellPresented = false
    /// Admin Tools' "Raise upsell": the onboarding pitch on its own, or the plain unlock sheet.
    @State private var isAdminPitchPresented = false
    @State private var isAdminUnlockPresented = false
    /// The tabs' bottom safe area, tab bar included.
    @State private var tabBarInset: CGFloat = 0
    /// The feed is about to replace onboarding, so its first deck deals in.
    @State private var dealsInDeck = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    private let router = NotificationRouter.shared
    private let devMode = DevMode.shared

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
            case .feed, .caughtUp:
                tabs
                    .transition(.opacity)
            }
        }
        .environment(\.dealsInFirstDeck, dealsInDeck)
        .animation(DS.Motion.gentle, value: vm.phase)
        .onChange(of: vm.phase) { old, new in
            // Only the feed that replaces onboarding deals in.
            if old != .onboarding, new != .onboarding { dealsInDeck = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // Refills earned while away land on return.
            if phase == .active { vm.refreshAllowance() }
        }
        .onChange(of: devMode.isEnabled) { _, enabled in
            // Developer mode went off with the Admin tab up: it's gone, so back to the feed.
            tab = AppTab.fallback(tab, devModeEnabled: enabled)
        }
        .onChange(of: router.feedRequests) {
            // A refill reminder was tapped.
            tab = .feed
        }
        .onChange(of: vm.adminShowFeedRequest) {
            // Admin Tools put a mock card on the deck.
            tab = .feed
        }
        .alert("Couldn't load your saved progress", isPresented: progressLoadNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your photos are untouched.")
        }
        .sheet(isPresented: $isPilePresented) {
            PendingPileView(showsDone: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .sheet(isPresented: $isUpsellPresented) {
            UnlockSheet(title: "Freed \(Format.size(vm.upsellFreedBytes))", subtitle: "Unlock to keep going without limits.")
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .task(id: vm.isDeleteUpsellDue) {
            guard vm.isDeleteUpsellDue else { return }
            // Let the pile finish closing first.
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, vm.isDeleteUpsellDue else { return }
            // Never over the wall, or once unlocked meanwhile.
            let shows = !vm.isWallPresented && !vm.isUnlocked
            if shows { isUpsellPresented = true }
            vm.finishDeleteUpsell(shown: shows)
        }
        .sheet(isPresented: $isAdminUnlockPresented) {
            UnlockSheet()
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.Palette.paper)
                .presentationCornerRadius(DS.Radius.card)
        }
        .fullScreenCover(isPresented: $isAdminPitchPresented) {
            UpsellView { isAdminPitchPresented = false }
                .background(DS.Palette.paper)
        }
        .task(id: vm.adminUpsellRequest) {
            guard let screen = vm.adminUpsellRequest else { return }
            // Let Settings finish closing first.
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            switch screen {
            case .postDelete: isUpsellPresented = true
            case .wall:
                tab = .feed
                vm.presentWall()
            case .onboarding: isAdminPitchPresented = true
            case .unlockSheet: isAdminUnlockPresented = true
            }
            vm.finishAdminUpsell()
        }
        .onChange(of: vm.isUnlocked) {
            vm.entitlementChanged()
        }
        .task(id: vm.isReviewPromptDue) {
            guard vm.isReviewPromptDue else { return }
            // Let the pile finish closing first.
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, vm.isReviewPromptDue else { return }
            // Never over the wall or right after a purchase.
            let asks = !vm.isWallPresented && !vm.purchasedThisLaunch
            if asks { requestReview() }
            vm.finishReviewPrompt(asked: asks)
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

    /// Shown once when saved progress couldn't be opened at launch.
    private var progressLoadNotice: Binding<Bool> {
        Binding(get: { vm.isProgressLoadNoticePresented }, set: { if !$0 { vm.dismissProgressLoadNotice() } })
    }

    /// Every tab stays mounted so the deck keeps its place while another is up.
    private var tabs: some View {
        ZStack {
            feedTab
                .tabVisibility(tab == .feed)
            LibraryView(isActive: tab == .library)
                .tabVisibility(tab == .library)
            if devMode.isEnabled {
                AdminToolsView(onOpenFeed: { tab = .feed }, onOpenLibrary: { tab = .library })
                    .tabVisibility(tab == .admin)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { tabBarInset = $0 }
        .environment(\.tabBarInset, tabBarInset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PillTabBar(items: AppTab.visible(devModeEnabled: devMode.isEnabled).map(\.tabItem), selection: $tab)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.xxs)
        }
    }

    @ViewBuilder
    private var feedTab: some View {
        switch vm.phase {
        case .caughtUp:
            CaughtUpView()
                .transition(.opacity)
        default:
            FeedView(onOpenPile: { isPilePresented = true })
                .transition(.opacity)
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

extension EnvironmentValues {
    /// How far the tab bar reaches up from the bottom edge, home indicator included. Zero outside the tabs.
    /// Screens pushed inside a tab don't always get the tab bar's inset, so they can pad by what's missing.
    @Entry var tabBarInset: CGFloat = 0
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
