import SwiftUI

/// The unlock: one-time purchase, what it includes, the buy button, and Restore beside a way out.
/// Shared by the swipe wall and Settings' unlock sheet; the purchase itself runs in `FeedViewModel`.
struct UnlockOffer: View {
    @Environment(FeedViewModel.self) private var vm
    /// The quiet button next to Restore, e.g. "Not now".
    var dismissTitle = "Not now"
    let onDismiss: () -> Void

    private var status: FeedViewModel.PaywallStatus { vm.paywallStatus }
    private var isPurchasing: Bool { status == .purchasing }
    private var isRestoring: Bool { status == .restoring }
    private var isBusy: Bool { vm.isPurchaseBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            oneTime
            bullets
                .padding(.top, DS.Spacing.m)
            actions
                .padding(.top, DS.Spacing.l)
        }
    }

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
            ForEach(["Unlimited swipes",
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
                    dismissButton
                    Spacer(minLength: DS.Spacing.m)
                    restore
                }
                VStack(spacing: DS.Spacing.s) {
                    dismissButton
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

    private var dismissButton: some View {
        Button(dismissTitle, action: onDismiss)
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

    private var message: String? {
        switch status {
        case .purchaseFailed: "The purchase didn't go through. You weren't charged."
        case .nothingToRestore: "We couldn't find an earlier purchase to restore."
        case .restoreFailed: "Couldn't reach the App Store. Try again in a moment."
        default: nil
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
