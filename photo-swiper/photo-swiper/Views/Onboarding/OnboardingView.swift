import SwiftUI

/// First launch: Welcome, the photo access primer, then reminders and the unlock offer where they
/// apply. Nothing asks for access until the primer's Continue. Once access is granted there's no
/// going back, and the first deck is dealt underneath while the last steps show.
struct OnboardingView: View {
    private enum Step { case welcome, access }

    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome

    /// How long the primer shows access granted before moving on, so its checkmark can be read.
    private static let grantedPause = Duration.seconds(0.9)

    var body: some View {
        ZStack {
            switch vm.onboardingStep {
            case .intro:
                switch step {
                case .welcome:
                    WelcomeView(pageCount: vm.onboardingPageCount) { go(to: .access) }
                        .transition(leaving(toward: .leading))
                case .access:
                    PhotoAccessPrimerView(progress: primerProgress, pageCount: vm.onboardingPageCount) {
                        Haptics.advance()
                        Task { await vm.start() }
                    }
                    // Back to Welcome until access is granted, then forward.
                    .transition(leaving(toward: vm.isOnboardingAccessGranted ? .leading : .trailing))
                    .simultaneousGesture(backSwipe)
                    .accessibilityAction(.escape) { go(to: .welcome) }
                }
            case .notifications:
                NotificationsPrimerView(page: vm.onboardingPageIndex, pageCount: vm.onboardingPageCount) {
                    advance()
                }
                .transition(leaving(toward: .leading))
            case .upsell:
                UpsellView(page: vm.onboardingPageIndex, pageCount: vm.onboardingPageCount) {
                    advance()
                }
                .transition(leaving(toward: .leading))
            }
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

    private var primerProgress: PhotoAccessPrimerView.Progress {
        if vm.isOnboardingAccessGranted { return .preparing }
        return vm.isRequestingAccess ? .requesting : .idle
    }

    private func go(to next: Step) {
        // No going back once the system prompt is up or access is granted.
        guard primerProgress == .idle else { return }
        withAnimation(pageAnimation) { step = next }
    }

    /// On to the next step after photo access, or the feed.
    private func advance() {
        Task { await vm.advanceOnboarding() }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : DS.Motion.page
    }

    /// The incoming page appears at once and runs its own staggered entrance; the outgoing one
    /// fades as it drifts a little toward `edge`. Pages only leave forward, except the primer,
    /// which can go back to Welcome until access is asked for.
    private func leaving(toward edge: Edge) -> AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : 32
        return .asymmetric(
            insertion: reduceMotion ? .opacity : .identity,
            // Clears out quickly, so the headlines don't double up as the next page enters.
            removal: .opacity.combined(with: .offset(x: edge == .leading ? -drift : drift))
                .animation(.easeOut(duration: 0.22))
        )
    }

    /// A swipe in from the left edge goes back to Welcome.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard value.startLocation.x < 40, value.translation.width > 80,
                      abs(value.translation.height) < value.translation.width else { return }
                go(to: .welcome)
            }
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
