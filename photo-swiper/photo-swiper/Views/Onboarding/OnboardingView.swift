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
                    .transition(slide(from: .leading))
            case .access:
                PhotoAccessPrimerView(progress: primerProgress) {
                    Task { await vm.start() }
                }
                .transition(slide(from: .trailing))
                .simultaneousGesture(backSwipe)
                .accessibilityAction(.escape) { go(to: .welcome) }
            }
        }
        .background(DS.Palette.paper)
    }

    private var primerProgress: PhotoAccessPrimerView.Progress {
        if vm.isPreparingFirstSession { return .preparing }
        return vm.isRequestingAccess ? .requesting : .idle
    }

    private func go(to next: Step) {
        // No going back once the system prompt is up or access is granted.
        guard primerProgress == .idle else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : DS.Motion.gentle) { step = next }
    }

    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge)
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
