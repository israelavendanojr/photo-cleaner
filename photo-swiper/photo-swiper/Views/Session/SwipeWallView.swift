import SwiftUI

/// Out of free swipes. A sheet over the deck, opened by a refused swipe: when the next refill
/// lands, what's left in the user's own numbers, the unlock, and a reminder. Deleting lives in the pile.
struct SwipeWallView: View {
    @Environment(FeedViewModel.self) private var vm

    private var status: FeedViewModel.PaywallStatus { vm.paywallStatus }
    private var isPurchasing: Bool { status == .purchasing }
    private var isRestoring: Bool { status == .restoring }
    private var isBusy: Bool { isPurchasing || isRestoring }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let estimate = vm.clutterEstimate {
                    whatsLeft(estimate)
                        .padding(.top, DS.Spacing.l)
                }
                if vm.freedBytes > 0 {
                    Text("Freed so far: \(Format.size(vm.freedBytes))")
                        .font(.callout)
                        .foregroundStyle(DS.Palette.secondary)
                        .padding(.top, DS.Spacing.m)
                }
                oneTime
                    .padding(.top, DS.Spacing.l)
                bullets
                    .padding(.top, DS.Spacing.m)
                actions
                    .padding(.top, DS.Spacing.l)
                if vm.canRemind {
                    reminder
                        .padding(.top, DS.Spacing.m)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.Palette.paper)
        .interactiveDismissDisabled(isBusy)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Out of swipes")
                .font(.subheadline)
                .foregroundStyle(DS.Palette.secondary)
                .accessibilityAddTraits(.isHeader)
            if let next = vm.nextRefillAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("+\(vm.allowanceTunables.refillAmount) in \(Format.countdown(next.timeIntervalSince(context.date)))")
                        .dsSerif(34, relativeTo: .largeTitle, weight: .medium)
                        .foregroundStyle(DS.Palette.ink)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("wall.countdown")
            }
        }
    }

    private func whatsLeft(_ estimate: ClutterEstimate) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Still to go, about")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
            if estimate.likelyClearBytes > 0 {
                line("\(Format.size(estimate.likelyClearBytes)) of likely clutter")
            }
            if estimate.similarGroupCount > 0 {
                line("\(Format.count(estimate.similarGroupCount)) \(estimate.similarGroupCount == 1 ? "set" : "sets") of similar shots")
            }
            if estimate.screenshotCount > 0 {
                line("\(Format.count(estimate.screenshotCount)) \(estimate.screenshotCount == 1 ? "screenshot" : "screenshots")")
            }
            if let days = vm.daysToFinish, days >= 2 {
                Text("At this pace, \(Format.roughDays(days)). Unlock to finish today.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(DS.Palette.ink)
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

    @ViewBuilder
    private var reminder: some View {
        if vm.isRemindersOptedIn {
            Label("We'll let you know when swipes are back", systemImage: "bell")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if vm.areRemindersDenied {
            Text("Notifications are off for \(AppInfo.name). You can turn them on in Settings.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await vm.remindWhenSwipesAreBack() }
            } label: {
                Label("Remind me when swipes are back", systemImage: "bell")
            }
            .buttonStyle(.pill(.ghost))
            .accessibilityIdentifier("wall.remind")
        }
    }

    private var notNow: some View {
        Button("Not now") {
            vm.dismissWall()
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

    private var message: String? {
        switch status {
        case .purchaseFailed: "The purchase didn't go through. You weren't charged."
        case .restoreFailed: "We couldn't find an earlier purchase to restore."
        default: nil
        }
    }

    private func unlock() {
        Task {
            if await vm.unlockFromWall() { Haptics.unlocked() }
        }
    }

    private func restorePurchase() {
        Task {
            if await vm.restoreFromWall() { Haptics.unlocked() }
        }
    }
}

#if DEBUG
#Preview("Out of swipes") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SwipeWallView()
        }
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
}

#Preview("Purchasing") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .purchasing)
    return SwipeWallView().environment(vm)
}

#Preview("Restore failed") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .restoreFailed)
    return SwipeWallView().environment(vm)
}
#endif
