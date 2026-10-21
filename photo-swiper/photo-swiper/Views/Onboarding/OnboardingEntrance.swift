import SwiftUI

/// Fades content up into place when an onboarding screen appears. Shows it at once with Reduce Motion.
struct OnboardingEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        let shown = isVisible || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(DS.Motion.gentle.delay(delay)) { isVisible = true }
            }
    }
}

extension View {
    func onboardingEntrance(delay: Double = 0) -> some View {
        modifier(OnboardingEntrance(delay: delay))
    }

    /// Scrolling content with the primary action pinned below it, so small screens and large
    /// text scroll instead of clipping.
    func onboardingLayout<Footer: View>(@ViewBuilder footer: () -> Footer) -> some View {
        ScrollView {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer()
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.m)
                .background(DS.Palette.paper)
                .overlay(alignment: .top) {
                    // Softens the edge where scrolled content meets the pinned button.
                    LinearGradient(colors: [DS.Palette.paper.opacity(0), DS.Palette.paper], startPoint: .top, endPoint: .bottom)
                        .frame(height: DS.Spacing.l)
                        .offset(y: -DS.Spacing.l)
                        .allowsHitTesting(false)
                }
        }
        .background(DS.Palette.paper)
    }
}
