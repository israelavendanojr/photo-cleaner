import SwiftUI

/// The free session is used up. A large card on paper, like a feed card but not swipeable:
/// unlock once, restore, or step away to the rest screen.
struct PaywallView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRisen = false

    private var status: FeedViewModel.PaywallStatus { vm.paywallStatus }
    private var isPurchasing: Bool { status == .purchasing }
    private var isRestoring: Bool { status == .restoring }
    private var isBusy: Bool { isPurchasing || isRestoring }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // Fills the screen at normal sizes; grows and scrolls with large text.
                card(minHeight: max(0, proxy.size.height - DS.Spacing.s - DS.Spacing.m))
                    .padding(.horizontal, DS.Spacing.cardInset)
                    .padding(.top, DS.Spacing.s)
                    .padding(.bottom, DS.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(DS.Palette.paper)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DS.Motion.gentle) { hasRisen = true }
        }
    }

    private func card(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You've reached the free limit")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .accessibilityAddTraits(.isHeader)
                .onboardingEntrance(order: 0)
            Text("That's your free cleanup, done.")
                .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.xs)
                .onboardingEntrance(order: 1)
            Text("To keep going, unlock \(AppInfo.name) once and it's yours for good.")
                .font(.callout)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.s)
                .onboardingEntrance(order: 2)
            oneTime
                .padding(.top, DS.Spacing.m)
                .onboardingEntrance(order: 3)
            if let personalLine {
                Text(personalLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.top, DS.Spacing.l)
                    .onboardingEntrance(order: 4)
            }
            bullets
                .padding(.top, personalLine == nil ? DS.Spacing.l : DS.Spacing.s)
                .onboardingEntrance(order: 5)
            Spacer(minLength: DS.Spacing.xl)
            actions
                .onboardingEntrance(order: 6)
        }
        .padding(DS.Spacing.l)
        .padding(.top, DS.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background {
            // Shadowing only the surface keeps the lift off the callout and the button.
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.card)
                .cardShadow()
        }
        .opacity(hasRisen || reduceMotion ? 1 : 0)
        .offset(y: hasRisen || reduceMotion ? 0 : 40)
    }

    // MARK: Sections

    private var oneTime: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("One-time purchase.")
                .dsSerif(22, relativeTo: .title3)
            Text("No subscription, no trial, no renewals.")
                .font(.footnote)
        }
        .foregroundStyle(DS.Palette.brick)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background(DS.Palette.brickTint, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ForEach(["Unlimited swiping, every month of your library",
                     "Similar-shot picks and screenshot batches",
                     "Future updates included"], id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Circle()
                        .fill(DS.Palette.brick)
                        .frame(width: 6, height: 6)
                        // Centers the dot on the first line's x-height.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        .accessibilityHidden(true)
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(DS.Palette.ink)
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.m) {
            Button(action: unlock) {
                ZStack {
                    Text("Unlock for \(vm.displayPrice)")
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .transition(.opacity)
                    }
                }
                .animation(DS.Motion.calm, value: isPurchasing)
            }
            .buttonStyle(.pill(.brick))
            .allowsHitTesting(!isBusy)
            .accessibilityLabel("Unlock for \(vm.displayPrice), one-time purchase")
            .accessibilityValue(isPurchasing ? "Purchasing" : "")
            .accessibilityIdentifier("paywall.unlock")

            ViewThatFits(in: .horizontal) {
                HStack {
                    notNow
                    Spacer(minLength: DS.Spacing.m)
                    restore
                }
                VStack(spacing: DS.Spacing.s) {
                    notNow
                    restore
                }
            }
            .font(.callout)
            .padding(.horizontal, DS.Spacing.xxs)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityIdentifier("paywall.message")
            }
        }
        .animation(DS.Motion.calm, value: status)
    }

    private var notNow: some View {
        Button("Not now") {
            vm.dismissPaywall()
        }
        .foregroundStyle(DS.Palette.ink)
        .disabled(isBusy)
        .frame(minHeight: 44)
        .accessibilityIdentifier("paywall.notNow")
    }

    private var restore: some View {
        Button(action: restorePurchase) {
            HStack(spacing: DS.Spacing.xs) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DS.Palette.secondary)
                }
                Text(isRestoring ? "Restoring…" : "Restore purchase")
            }
        }
        .foregroundStyle(DS.Palette.secondary)
        .disabled(isBusy)
        .frame(minHeight: 44)
        .accessibilityIdentifier("paywall.restore")
    }

    // MARK: Helpers

    /// One honest line from the user's own library. Nothing estimated.
    private var personalLine: String? {
        guard vm.stats.totalItems > 0 else { return nil }
        let percent = Int((vm.libraryReviewedFraction * 100).rounded())
        if percent >= 1 { return "You've reviewed \(percent)% of your library." }
        let left = vm.photosLeftToReview
        return "\(left.formatted()) \(left == 1 ? "photo" : "photos") left to look through."
    }

    private var message: String? {
        switch status {
        case .purchaseFailed: "The purchase didn't go through. You weren't charged."
        case .restoreFailed: "We couldn't find an earlier purchase to restore."
        default: nil
        }
    }

    private func unlock() {
        Task {
            if await vm.unlockFromPaywall() { Haptics.unlocked() }
        }
    }

    private func restorePurchase() {
        Task {
            if await vm.restoreFromPaywall() { Haptics.unlocked() }
        }
    }
}

#if DEBUG
#Preview("Idle") {
    PaywallView()
        .environment(FeedViewModel.mock(startingAt: .paywall))
}

#Preview("Purchasing") {
    let vm = FeedViewModel.mock(startingAt: .paywall)
    vm.previewPaywall(status: .purchasing)
    return PaywallView().environment(vm)
}

#Preview("Restore failed") {
    let vm = FeedViewModel.mock(startingAt: .paywall)
    vm.previewPaywall(status: .restoreFailed)
    return PaywallView().environment(vm)
}
#endif
