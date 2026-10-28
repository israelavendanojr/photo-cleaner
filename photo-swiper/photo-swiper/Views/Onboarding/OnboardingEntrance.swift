import SwiftUI

/// Fades content up into place when an onboarding screen appears. Shows it at once with Reduce Motion.
struct OnboardingEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.onboardingEntranceSettled) private var isSettled
    @State private var isVisible = false

    /// Gap between one element's entrance and the next.
    static let step = 0.09
    /// Lets the previous page clear before the first element arrives.
    static let lead = 0.12

    func body(content: Content) -> some View {
        let shown = isVisible || reduceMotion || isSettled
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !reduceMotion else { return }
                guard !isSettled else {
                    isVisible = true
                    return
                }
                withAnimation(DS.Motion.gentle.delay(delay)) { isVisible = true }
            }
    }
}

extension EnvironmentValues {
    /// The screen is being revealed by going back, so it shows already in place instead of entering.
    @Entry var onboardingEntranceSettled = false
    /// Room this screen leaves at the top for onboarding's back button. None on Welcome, which has none.
    @Entry var onboardingTopInset: CGFloat = 0
}

/// Pads scrolling onboarding content below the top bar, where there is one.
private struct OnboardingTopPadding: ViewModifier {
    @Environment(\.onboardingTopInset) private var inset

    func body(content: Content) -> some View {
        content.padding(.top, DS.Spacing.l + inset)
    }
}

extension View {
    /// Enters `order` steps after the screen's first element.
    func onboardingEntrance(order: Int) -> some View {
        modifier(OnboardingEntrance(delay: OnboardingEntrance.lead + Double(order) * OnboardingEntrance.step))
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
                .modifier(OnboardingTopPadding())
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
