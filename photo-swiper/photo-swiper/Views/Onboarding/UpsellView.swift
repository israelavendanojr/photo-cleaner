import SwiftUI

/// Onboarding's last step: what the free version gives, plainly, then the same unlock offer as the
/// wall. Carrying on for free is one tap, from the close button in onboarding's top bar or beside Restore.
/// A purchase or restore moves on by itself.
struct UpsellView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.onboardingTopInset) private var topInset
    /// Leaves onboarding, free or unlocked.
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.headline)
                    .dsSerif(40, relativeTo: .largeTitle, weight: .medium)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, DS.Spacing.l)
                    .onboardingEntrance(order: 0)
                freeTier
                    .padding(.top, DS.Spacing.l)
                    .onboardingEntrance(order: 1)
                UnlockOffer(dismissTitle: Copy.continueFree, onDismiss: continueFree)
                    .padding(.top, DS.Spacing.xl)
                    .onboardingEntrance(order: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.s + topInset)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
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

    private var freeTier: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text(Copy.freeTierTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
            FreeTierRow(systemImage: "hand.draw", text: Copy.swipes(vm.allowanceTunables))
            FreeTierRow(systemImage: "trash", text: Copy.pile(FeedViewModel.freePileCap))
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .softShadow()
        .accessibilityElement(children: .combine)
    }

    /// Shown in the rare case the first deck is still being built when the user leaves.
    private var preparing: some View {
        HStack(spacing: DS.Spacing.xs) {
            ProgressView()
                .tint(DS.Palette.secondary)
            Text(Copy.preparing)
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.m)
        .background(DS.Palette.paper)
        .transition(.opacity)
    }

    private func continueFree() {
        guard !vm.isPurchaseBusy else { return }
        Haptics.advance()
        onContinue()
    }
}

/// This screen's words, together so they're easy to change. Numbers come from the allowance and pile limits.
private enum Copy {
    static let headline = "Free to use. Unlimited if you like."
    static let freeTierTitle = "The free version includes"
    static let continueFree = "Continue for free"
    static let preparing = "Finding your first photos…"

    /// "20 swipes to start, then 10 more every 6 hours."
    static func swipes(_ tunables: SwipeAllowance.Tunables) -> String {
        let every = Duration.seconds(tunables.refillInterval)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return "\(tunables.cap) swipes to start, then \(tunables.refillAmount) more every \(every)."
    }

    /// "Up to 50 photos waiting to delete at a time. Delete them and keep going."
    static func pile(_ cap: Int) -> String {
        "Up to \(cap) photos waiting to delete at a time. Delete them and keep going."
    }
}

private struct FreeTierRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    UpsellView(onContinue: {})
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock())
}

#Preview("Purchasing") {
    let vm = FeedViewModel.mock()
    vm.previewWall(status: .purchasing)
    return UpsellView(onContinue: {})
        .background(DS.Palette.paper)
        .environment(vm)
}
#endif
