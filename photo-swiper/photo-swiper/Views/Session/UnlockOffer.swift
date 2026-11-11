import SwiftUI

/// The unlock: what it includes, the buy button and how it's billed, a way out, then Restore and the
/// legal links. Shared by the swipe wall, the unlock sheets and onboarding; the purchase itself runs
/// in `FeedViewModel`. The words are in `UnlockCopy`.
struct UnlockOffer: View {
    /// `.standard` is the shared look of the wall and the sheets. `.onboarding` keeps the pitch's own
    /// look (the one-time box, Restore beside the way out), since that screen is meant to stand apart.
    enum Style { case standard, onboarding }

    @Environment(FeedViewModel.self) private var vm
    var style: Style = .standard
    /// The way out, e.g. "Not now".
    var dismissTitle = "Not now"
    let onDismiss: () -> Void

    private var status: PaywallStatus { vm.paywallStatus }
    private var isPurchasing: Bool { status == .purchasing }
    private var isRestoring: Bool { status == .restoring }
    private var isBusy: Bool { vm.isPurchaseBusy }

    var body: some View {
        Group {
            switch style {
            case .standard: standard
            case .onboarding: onboarding
            }
        }
        .animation(DS.Motion.calm, value: status)
    }

    // MARK: Standard

    private var standard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text(UnlockCopy.includedTitle)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                ForEach(UnlockCopy.included, id: \.text) { item in
                    IncludedRow(systemImage: item.systemImage, text: item.text)
                }
            }
            .accessibilityElement(children: .combine)

            unlockButton
                .padding(.top, DS.Spacing.xl)
            Text(UnlockCopy.priceNote)
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.s)

            Button(dismissTitle, action: onDismiss)
                .buttonStyle(.pill(.ghost))
                .disabled(isBusy)
                .accessibilityIdentifier("paywall.notNow")
                .padding(.top, DS.Spacing.xs)

            messageText
                .padding(.top, DS.Spacing.xs)

            footer
                .padding(.top, DS.Spacing.s)
        }
    }

    /// "Restore purchase · Privacy · Terms", stacked when it won't fit on one line.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                restore
                Text("·")
                    .accessibilityHidden(true)
                LegalLinks()
                    .fixedSize()
            }
            VStack(spacing: 0) {
                restore
                LegalLinks()
            }
        }
        .font(.footnote)
        .foregroundStyle(DS.Palette.secondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: Onboarding

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 0) {
            oneTimeBox
            bullets
                .padding(.top, DS.Spacing.m)
            VStack(spacing: DS.Spacing.m) {
                unlockButton
                ViewThatFits(in: .horizontal) {
                    HStack {
                        quietDismiss
                        Spacer(minLength: DS.Spacing.m)
                        restore
                    }
                    VStack(spacing: DS.Spacing.s) {
                        quietDismiss
                        restore
                    }
                }
                .font(.callout)
                .padding(.horizontal, DS.Spacing.xxs)
                messageText
                LegalLinks()
            }
            .padding(.top, DS.Spacing.l)
        }
    }

    private var oneTimeBox: some View {
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
            ForEach(UnlockCopy.included, id: \.text) { item in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Circle()
                        .fill(DS.Palette.brick)
                        .frame(width: 6, height: 6)
                        // Centers the dot on the first line's x-height.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        .accessibilityHidden(true)
                    Text(item.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(DS.Palette.ink)
    }

    private var quietDismiss: some View {
        Button(dismissTitle, action: onDismiss)
            .foregroundStyle(DS.Palette.ink)
            .disabled(isBusy)
            .frame(minHeight: 44)
            .accessibilityIdentifier("paywall.notNow")
    }

    // MARK: Shared pieces

    private var unlockButton: some View {
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

    @ViewBuilder
    private var messageText: some View {
        if let message = UnlockCopy.message(for: status) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .accessibilityIdentifier("paywall.message")
        }
    }

    private func unlock() {
        Task {
            if await vm.purchaseUnlock() { Haptics.unlocked() }
        }
    }

    private func restorePurchase() {
        Task {
            if await vm.restorePurchases() { Haptics.unlocked() }
        }
    }
}
