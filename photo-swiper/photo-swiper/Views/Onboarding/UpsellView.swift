import SwiftUI

/// Onboarding's last step: the paywall, the same screen as everywhere else. Carrying on for free is one tap
/// on the close button in onboarding's top bar; shown on its own (Admin Tools), it draws its own. A purchase
/// or restore moves on by itself.
struct UpsellView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.onboardingTopInset) private var topInset
    /// True when nothing around it offers a way out.
    var showsClose = false
    /// Leaves onboarding, free or unlocked.
    let onContinue: () -> Void

    var body: some View {
        PaywallView(showsClose: showsClose, topInset: topInset, onClose: continueFree)
            .allowsHitTesting(!vm.isLeavingOnboarding)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if vm.isLeavingOnboarding { preparing }
            }
            .animation(DS.Motion.calm, value: vm.isLeavingOnboarding)
            .onAppear { vm.resetPurchaseStatus() }
            .onChange(of: vm.isUnlocked) { _, unlocked in
                if unlocked { onContinue() }
            }
    }

    /// Shown in the rare case the first deck is still being built when the user leaves.
    private var preparing: some View {
        HStack(spacing: DS.Spacing.xs) {
            ProgressView()
                .tint(DS.Palette.secondary)
            Text("Finding your first photos…")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.m)
        .transition(.opacity)
    }

    private func continueFree() {
        guard !vm.isPurchaseBusy else { return }
        Haptics.advance()
        onContinue()
    }
}

#if DEBUG
#Preview {
    UpsellView(showsClose: true, onContinue: {})
        .environment(FeedViewModel.mock())
}

#Preview("Dark") {
    UpsellView(showsClose: true, onContinue: {})
        .environment(FeedViewModel.mock())
        .preferredColorScheme(.dark)
}
#endif
