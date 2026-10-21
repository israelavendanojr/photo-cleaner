import SwiftUI

/// Fades content up into place when an onboarding screen appears. Shows it at once with Reduce Motion.
struct OnboardingEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    /// Gap between one element's entrance and the next.
    static let step = 0.09

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
    /// Enters `order` steps after the screen's first element.
    func onboardingEntrance(order: Int) -> some View {
        modifier(OnboardingEntrance(delay: Double(order) * OnboardingEntrance.step))
    }

    /// Scrolling content with the primary action pinned below it, so small screens and large
    /// text scroll instead of clipping. The footer enters at `footerOrder`, after the content.
    ///
    /// Only the footer is opaque, so a screen leaving underneath stays visible while this one enters.
    func onboardingLayout<Footer: View>(footerOrder: Int, @ViewBuilder footer: () -> Footer) -> some View {
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
                .onboardingEntrance(order: footerOrder)
        }
    }
}
