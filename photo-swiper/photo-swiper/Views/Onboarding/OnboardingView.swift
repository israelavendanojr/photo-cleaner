import SwiftUI

/// First launch: Welcome, then the photo access primer. Nothing asks for access until its Continue.
struct OnboardingView: View {
    private enum Step { case welcome, access }

    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView { go(to: .access) }
                    .transition(leaving(toward: .leading))
            case .access:
                PhotoAccessPrimerView(progress: primerProgress) {
                    Haptics.advance()
                    Task { await vm.start() }
                }
                .transition(leaving(toward: .trailing))
                .simultaneousGesture(backSwipe)
                .accessibilityAction(.escape) { go(to: .welcome) }
            }
        }
        .background(DS.Palette.paper)
        .onChange(of: vm.isPreparingFirstSession) { _, isPreparing in
            // Only full or limited access gets here; a denial goes straight to the no-access screen.
            if isPreparing { Haptics.accessGranted() }
        }
    }

    private var primerProgress: PhotoAccessPrimerView.Progress {
        if vm.isPreparingFirstSession { return .preparing }
        return vm.isRequestingAccess ? .requesting : .idle
    }

    private func go(to next: Step) {
        // No going back once the system prompt is up or access is granted.
        guard primerProgress == .idle else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : DS.Motion.page) { step = next }
    }

    /// The incoming page appears at once and runs its own staggered entrance; the outgoing one
    /// fades as it drifts a little toward `edge`. Welcome only ever leaves forward and the primer
    /// only ever leaves back, so each page's direction is fixed.
    private func leaving(toward edge: Edge) -> AnyTransition {
        let drift: CGFloat = reduceMotion ? 0 : 32
        return .asymmetric(
            insertion: reduceMotion ? .opacity : .identity,
            removal: .opacity.combined(with: .offset(x: edge == .leading ? -drift : drift))
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

#Preview {
    OnboardingView()
        .environment(FeedViewModel.mock(startingAt: .onboarding))
}
