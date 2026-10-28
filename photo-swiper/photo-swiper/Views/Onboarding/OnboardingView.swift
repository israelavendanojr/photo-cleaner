import SwiftUI

/// First launch: Welcome, the photo access primer, then reminders and the unlock offer where they
/// apply. Nothing asks for access until the primer's Continue. Once access is granted the first deck
/// is dealt underneath while the last steps show.
///
/// Every page after Welcome can go back, from the back button or a swipe in from the left edge that
/// follows the finger, with the previous page sliding in underneath. Going back past photo access
/// shows it granted, so it never asks twice.
struct OnboardingView: View {
    enum Page: Hashable { case welcome, access, notifications, upsell }

    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Welcome or the primer, while the view model's step is `.intro`.
    @State private var introPage = Page.welcome
    /// The user has come back to the primer after access was granted, so it offers a plain Continue.
    @State private var hasRevisitedAccess = false
    /// How far the current page has been pulled back, in points.
    @State private var dragX: CGFloat = 0
    /// A back move is running, so the previous page stays drawn underneath until it lands.
    @State private var isGoingBack = false
    /// Whether the drag in progress is a back swipe. Decided on its first movement.
    @State private var isTrackingBack: Bool?
    @State private var hasCrossedCommit = false

    /// How long the primer shows access granted before moving on, so its checkmark can be read.
    private static let grantedPause = Duration.seconds(0.9)
    /// A back swipe has to start this close to the leading edge, so scrolling and buttons are left alone.
    private static let edgeWidth: CGFloat = 30
    /// Share of the width past which letting go finishes going back.
    private static let commitFraction: CGFloat = 0.35
    /// How far the previous page sits behind, as a share of its distance from the current one.
    private static let parallax: CGFloat = 0.3
    /// The back button and the space around it, which pages after Welcome start below.
    private static let topBarHeight: CGFloat = 44 + DS.Spacing.xs

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ForEach(visiblePages, id: \.self) { page in
                    pageLayer(page, width: width)
                }
            }
            // Over the pages rather than above them, so Welcome keeps the room it doesn't need for it.
            .overlay(alignment: .top) { topBar(width: width) }
            .simultaneousGesture(backSwipe(width: width))
            .accessibilityAction(.escape) { goBack(width: width) }
        }
        .background(DS.Palette.paper)
        // The steps after access change in the view model, often after an await, so they animate here.
        .animation(pageAnimation, value: vm.onboardingStep)
        .task(id: vm.isOnboardingAccessGranted) {
            // Only full or limited access gets here; a denial goes straight to the no-access screen.
            guard vm.isOnboardingAccessGranted, vm.onboardingStep == .intro else { return }
            Haptics.accessGranted()
            try? await Task.sleep(for: Self.grantedPause)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    // MARK: Pages

    /// Welcome, photo access, then the steps after it that apply.
    private var pages: [Page] {
        var pages: [Page] = [.welcome, .access]
        if vm.offersReminderStep { pages.append(.notifications) }
        if vm.offersUpsellStep { pages.append(.upsell) }
        return pages
    }

    private var current: Page {
        switch vm.onboardingStep {
        case .intro: introPage
        case .notifications: .notifications
        case .upsell: .upsell
        }
    }

    private var previous: Page? {
        guard let index = pages.firstIndex(of: current), index > 0 else { return nil }
        return pages[index - 1]
    }

    /// The previous page is only drawn while it's being revealed.
    private var showsPrevious: Bool { dragX > 0 || isGoingBack }

    private var visiblePages: [Page] {
        if showsPrevious, let previous { return [previous, current] }
        return [current]
    }

    private func pageLayer(_ page: Page, width: CGFloat) -> some View {
        let isCurrent = page == current
        let progress = backProgress(width: width)
        return pageView(page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Opaque only while it's pulled over the previous page; forward changes cross-fade.
            .background(isCurrent && showsPrevious ? DS.Palette.paper : .clear)
            .shadow(color: .black.opacity(isCurrent && showsPrevious ? 0.1 : 0), radius: 18, x: -6)
            .overlay {
                if !isCurrent {
                    // Lifts as the previous page comes forward.
                    DS.Palette.ink.opacity(0.06 * (1 - progress))
                        .allowsHitTesting(false)
                }
            }
            .offset(x: isCurrent ? dragX : (dragX - width) * Self.parallax)
            // Shown in place under the swipe rather than entering.
            .environment(\.onboardingEntranceSettled, !isCurrent)
            .environment(\.onboardingTopInset, page == .welcome ? 0 : Self.topBarHeight)
            .allowsHitTesting(isCurrent && !showsPrevious)
            .accessibilityHidden(!isCurrent)
            .zIndex(isCurrent ? 1 : 0)
            // A page leaving by going back has already slid away, so it goes at once.
            .transition(isCurrent && isGoingBack ? .identity : leaving)
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        let index = pages.firstIndex(of: page) ?? 0
        switch page {
        case .welcome:
            WelcomeView(pageCount: pages.count) { go(to: .access) }
        case .access:
            PhotoAccessPrimerView(progress: primerProgress(isCurrent: page == current), pageCount: pages.count) {
                Haptics.advance()
                if vm.isOnboardingAccessGranted {
                    advance()
                } else {
                    Task { await vm.start() }
                }
            }
        case .notifications:
            NotificationsPrimerView(page: index, pageCount: pages.count) { advance() }
        case .upsell:
            UpsellView(page: index, pageCount: pages.count) { advance() }
        }
    }

    /// The primer just after access is granted shows the first deck underway, then moves on.
    /// Seen again, it offers a plain Continue.
    private func primerProgress(isCurrent: Bool) -> PhotoAccessPrimerView.Progress {
        if vm.isOnboardingAccessGranted {
            return hasRevisitedAccess || !isCurrent ? .granted : .preparing
        }
        return vm.isRequestingAccess ? .requesting : .idle
    }

    // MARK: Top bar

    private func topBar(width: CGFloat) -> some View {
        let progress = backProgress(width: width)
        return HStack {
            CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                goBack(width: width)
            }
            // Fades out as Welcome, which has nowhere to go back to, comes in.
            .opacity(current == .welcome ? 0 : previous == .welcome ? 1 - progress : 1)
            .opacity(canGoBack ? 1 : 0.4)
            .disabled(!canGoBack)
            .accessibilityHidden(current == .welcome)
            .accessibilityIdentifier("onboarding.back")
            Spacer()
            if current == .upsell {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Continue for free", action: continueFree)
                    .opacity(1 - progress)
                    .disabled(vm.isPurchaseBusy || vm.isLeavingOnboarding)
                    .accessibilityIdentifier("onboarding.upsell.close")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.xs)
        .animation(pageAnimation, value: current)
        .animation(DS.Motion.calm, value: canGoBack)
    }

    private func continueFree() {
        guard !vm.isPurchaseBusy else { return }
        Haptics.advance()
        advance()
    }

    // MARK: Moving between pages

    private var canGoBack: Bool {
        switch current {
        case .welcome: false
        // Not while the system prompt is up or the granted checkmark is showing.
        case .access: [.idle, .granted].contains(primerProgress(isCurrent: true))
        case .notifications, .upsell: vm.canGoBackInOnboarding
        }
    }

    /// Forward from Welcome to the primer.
    private func go(to next: Page) {
        withAnimation(pageAnimation) { introPage = next }
    }

    /// On to the next step after photo access, or the feed.
    private func advance() {
        Task { await vm.advanceOnboarding() }
    }

    /// Slides the current page off to the right and brings the previous one forward. With Reduce
    /// Motion the two cross-fade instead.
    private func goBack(width: CGFloat) {
        guard canGoBack, !isGoingBack else { return }
        Haptics.advance()
        guard !reduceMotion else {
            withAnimation(pageAnimation) { stepBack() }
            return
        }
        let alreadyRevealed = dragX > 0
        isGoingBack = true
        let slide = {
            withAnimation(DS.Motion.page) {
                dragX = width
            } completion: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    stepBack()
                    dragX = 0
                    isGoingBack = false
                }
            }
        }
        // From the button, the previous page has to be drawn in its starting place before it can slide.
        if alreadyRevealed { slide() } else { DispatchQueue.main.async(execute: slide) }
    }

    private func stepBack() {
        switch current {
        case .welcome:
            break
        case .access:
            introPage = .welcome
        case .notifications, .upsell:
            vm.goBackInOnboarding()
            if vm.onboardingStep == .intro {
                introPage = .access
                hasRevisitedAccess = true
            }
        }
    }

    /// How far a back move has got, from 0 to 1.
    private func backProgress(width: CGFloat) -> CGFloat {
        width > 0 ? min(max(dragX / width, 0), 1) : 0
    }

    /// A swipe in from the left edge pulls the page back with the finger. Let go past about a third of
    /// the way, or with a flick, and it finishes; otherwise it springs back.
    private func backSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if isTrackingBack == nil {
                    isTrackingBack = canGoBack && !isGoingBack
                        && value.startLocation.x < Self.edgeWidth
                        && value.translation.width > abs(value.translation.height)
                }
                guard isTrackingBack == true else { return }
                let pulled = max(0, value.translation.width)
                let crossed = pulled > width * Self.commitFraction
                if crossed != hasCrossedCommit {
                    hasCrossedCommit = crossed
                    if crossed { Haptics.threshold() }
                }
                // Reduce Motion doesn't track the finger; the change happens on release.
                if !reduceMotion { dragX = pulled }
            }
            .onEnded { value in
                defer {
                    isTrackingBack = nil
                    hasCrossedCommit = false
                }
                guard isTrackingBack == true else { return }
                let commits = value.translation.width > width * Self.commitFraction
                    || value.predictedEndTranslation.width > width * 0.6
                if commits {
                    goBack(width: width)
                } else {
                    withAnimation(DS.Motion.page) { dragX = 0 }
                }
            }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : DS.Motion.page
    }

    /// The incoming page appears at once and runs its own staggered entrance; the outgoing one
    /// fades as it drifts a little to the left. Going back has its own slide, above.
    private var leaving: AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : 32
        return .asymmetric(
            insertion: reduceMotion ? .opacity : .identity,
            // Clears out quickly, so the headlines don't double up as the next page enters.
            removal: .opacity.combined(with: .offset(x: -drift))
                .animation(.easeOut(duration: 0.22))
        )
    }
}

#if DEBUG
#Preview {
    let vm = FeedViewModel.mock(startingAt: .onboarding)
    OnboardingView()
        .environment(vm)
        // Puts the mock in onboarding, as launch does.
        .task { await vm.start() }
}
#endif
