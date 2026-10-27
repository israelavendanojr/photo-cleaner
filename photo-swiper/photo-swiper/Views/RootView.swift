import StoreKit
import SwiftUI

/// Switches between onboarding, the tabs (feed and library), and the access states.
struct RootView: View {
    @Environment(FeedViewModel.self) private var vm
    @State private var tab: AppTab = .feed
    @State private var isPilePresented = false
    /// The unlock offered after a free user's delete.
    @State private var isUpsellPresented = false
    /// The feed is about to replace onboarding, so its first deck deals in.
    @State private var dealsInDeck = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    private let router = NotificationRouter.shared

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
        .onChange(of: router.feedRequests) {
            // A refill reminder was tapped.
            tab = .feed
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
            if !vm.isWallPresented, !vm.isUnlocked { isUpsellPresented = true }
            vm.finishDeleteUpsell()
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
