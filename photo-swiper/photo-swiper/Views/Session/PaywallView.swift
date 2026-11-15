import SwiftUI

/// The paywall, one screen wherever the unlock is offered: the swipe wall, after a free user's delete,
/// Settings, and onboarding's last step. A small stack of photos, what unlocking adds, the plans, one brick
/// button that names the chosen plan and its price, how that plan is billed, and Restore.
///
/// The plans and their prices come from the store (`vm.unlockPlans`), never from here; a plan the store
/// doesn't list isn't shown. The purchase itself runs in `FeedViewModel`. The words are in `UnlockCopy`.
struct PaywallView: View {
    @Environment(FeedViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// False where the screen around it already has a way out (onboarding's top bar).
    var showsClose = true
    /// Space to leave above the content, under a bar drawn over it.
    var topInset: CGFloat = 0
    let onClose: () -> Void

    /// The plan the user picked. Nil follows the store's first.
    @State private var picked: UnlockPlan.Kind?
    /// The store is being asked for plans it hasn't listed.
    @State private var isLoadingPlans = false

    private var plans: [UnlockPlan] { vm.unlockPlans }
    private var selected: UnlockPlan? { plans.first { $0.kind == picked } ?? plans.first }
    private var status: PaywallStatus { vm.paywallStatus }
    private var isPurchasing: Bool { status == .purchasing }
    private var isRestoring: Bool { status == .restoring }
    private var isBusy: Bool { vm.isPurchaseBusy }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if showsClose {
                        CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
                            .disabled(isBusy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("paywall.close")
                    }
                    PaywallHero()
                        .padding(.top, DS.Spacing.xs)
                    Text(UnlockCopy.headline)
                        .dsSerif(36, relativeTo: .largeTitle, weight: .medium)
                        .tracking(-0.8)
                        .foregroundStyle(DS.Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Spacing.xl)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("paywall.title")
                    Text(UnlockCopy.supporting)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Spacing.xs)
                    benefits
                        .padding(.top, DS.Spacing.l)
                    Group {
                        if plans.isEmpty {
                            plansMissing
                        } else {
                            planCards
                        }
                    }
                    .padding(.top, DS.Spacing.l)
                }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.s + topInset)
                .padding(.bottom, DS.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
        }
        .paperBackground()
        .animation(DS.Motion.calm, value: status)
        .task { await loadPlans() }
    }

    /// The store lists a plan only once it has its price, so a launch with no network leaves some out.
    private func loadPlans() async {
        guard !isLoadingPlans else { return }
        isLoadingPlans = true
        await vm.reloadUnlockPlans()
        isLoadingPlans = false
    }

    // MARK: Benefits

    private var benefits: some View {
        VStack(spacing: 0) {
            ForEach(UnlockCopy.benefits, id: \.title) { benefit in
                Rule()
                BenefitRow(benefit: benefit)
            }
            Rule()
        }
    }

    // MARK: Plans

    private var planCards: some View {
        // Side by side; one under the other where two columns would squeeze the prices.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Spacing.s))
        return layout {
            ForEach(plans) { plan in
                PlanCard(plan: plan, isSelected: plan.kind == selected?.kind) {
                    guard plan.kind != selected?.kind else { return }
                    Haptics.planChosen()
                    withAnimation(reduceMotion ? nil : DS.Motion.planSelect) { picked = plan.kind }
                }
                .disabled(isBusy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plans")
    }

    /// No plan to show: the store hasn't given a price, and one is never made up here.
    private var plansMissing: some View {
        VStack(spacing: DS.Spacing.s) {
            if isLoadingPlans {
                ProgressView()
                    .tint(DS.Palette.secondary)
                Text(UnlockCopy.plansLoading)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
            } else {
                Text(UnlockCopy.plansUnavailable)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(UnlockCopy.plansRetry) {
                    Task { await loadPlans() }
                }
                .buttonStyle(.pill(.outline))
                .accessibilityIdentifier("paywall.retryPlans")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.plansMissing")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let selected {
                buyButton(selected)
            }
            if let message = UnlockCopy.message(for: status) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xs)
                    .transition(.opacity)
                    .accessibilityIdentifier("paywall.message")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.xs) {
                    billingNote
                    restore
                }
                VStack(spacing: 0) {
                    billingNote
                        .padding(.top, DS.Spacing.xs)
                    restore
                }
            }
            LegalLinks()
        }
    }

    private func buyButton(_ plan: UnlockPlan) -> some View {
        Button {
            Task {
                if await vm.purchaseUnlock(plan.kind) { Haptics.unlocked() }
            }
        } label: {
            ZStack {
                Text(UnlockCopy.buttonTitle(for: plan))
                    .contentTransition(reduceMotion ? .identity : .interpolate)
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
        .accessibilityLabel(UnlockCopy.buttonAccessibilityLabel(for: plan))
        .accessibilityValue(isPurchasing ? "Purchasing" : "")
        .accessibilityIdentifier("paywall.unlock")
    }

    @ViewBuilder private var billingNote: some View {
        if let selected {
            Text(UnlockCopy.billingNote(for: selected))
                .font(.footnote)
                .foregroundStyle(DS.Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(reduceMotion ? .identity : .interpolate)
                .accessibilityIdentifier("paywall.billingNote")
        }
    }

    private var restore: some View {
        Button {
            Task {
                if await vm.restorePurchases() { Haptics.unlocked() }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DS.Palette.secondary)
                }
                Text(isRestoring ? "Restoring…" : "Restore")
                    .underline()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DS.Palette.ink)
            .frame(minWidth: DS.Tap.minimum, minHeight: DS.Tap.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isRestoring ? "Restoring" : "Restore purchase")
        .accessibilityIdentifier("paywall.restore")
    }
}

/// One thing the unlock adds: an icon, what it is, and a line on what that means.
private struct BenefitRow: View {
    let benefit: UnlockCopy.Benefit
    @ScaledMetric(relativeTo: .body) private var iconWidth = DS.Paywall.iconColumn

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            Image(systemName: benefit.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: iconWidth, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(benefit.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
                Text(benefit.detail)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: DS.Paywall.benefitMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// A plan to choose: its name, a mark for whether it's the chosen one, its price, and how it's paid.
private struct PlanCard: View {
    let plan: UnlockPlan
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var mark = DS.Paywall.mark

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Paywall.planRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text(UnlockCopy.title(for: plan.kind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                    Spacer(minLength: DS.Spacing.xs)
                    selectionMark
                }
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xxs) {
                    Text(plan.displayPrice)
                        .dsSerif(38, relativeTo: .largeTitle)
                        .tracking(-1)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let suffix = UnlockCopy.priceSuffix(for: plan.kind) {
                        Text(suffix)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Text(UnlockCopy.detail(for: plan.kind))
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Paywall.planInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                // The shadow goes on the shape, so the text inside doesn't get a halo.
                shape
                    .fill(DS.Palette.card)
                    .softShadow(raised: true)
            }
            .overlay {
                shape.strokeBorder(
                    isSelected ? DS.Palette.ink : DS.Palette.outline,
                    lineWidth: isSelected ? DS.Paywall.selectedRing : DS.Control.ring
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(UnlockCopy.title(for: plan.kind)), \(plan.displayPrice)\(UnlockCopy.priceSuffix(for: plan.kind).map { " \($0)" } ?? ""). \(UnlockCopy.detail(for: plan.kind))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("paywall.plan.\(plan.kind.rawValue)")
    }

    /// A filled ink disc with a tick when chosen, an empty ring when not.
    private var selectionMark: some View {
        ZStack {
            Circle()
                .strokeBorder(DS.Palette.secondary, lineWidth: DS.Control.ring)
                .opacity(isSelected ? 0 : 1)
            Circle()
                .fill(DS.Palette.ink)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(DS.Palette.onInk)
                }
                .scaleEffect(isSelected ? 1 : 0.4)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: mark, height: mark)
        .accessibilityHidden(true)
    }
}

/// Three photos in a loose pile. They start squared up and fan out as the screen appears; with Reduce
/// Motion they're simply fanned.
private struct PaywallHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var width = DS.Paywall.heroWidth
    @State private var isFanned = false

    /// Back to front: the picture, how far it turns, and where it slides to.
    private static let photos: [(image: String, degrees: Double, x: CGFloat, y: CGFloat)] = [
        ("photo-coast", -11, -16, 4),
        ("photo-hills", 9, 16, 6),
        ("photo-sunset", -1, 0, 0),
    ]

    var body: some View {
        let fanned = isFanned || reduceMotion
        ZStack {
            ForEach(Self.photos, id: \.image) { photo in
                Image(photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: width * DS.Paywall.heroAspect)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Paywall.heroRadius, style: .continuous))
                    .cardShadow()
                    .offset(x: fanned ? photo.x : 0, y: fanned ? photo.y : 0)
                    .rotationEffect(.degrees(fanned ? photo.degrees : 0))
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DS.Motion.fan) { isFanned = true }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Paywall") {
    PaywallView {}
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
}

#Preview("Dark") {
    PaywallView {}
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
        .preferredColorScheme(.dark)
}

#Preview("XXL") {
    PaywallView {}
        .environment(FeedViewModel.mock(startingAt: .outOfSwipes))
        .dynamicTypeSize(.xxLarge)
}

#Preview("Purchasing") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .purchasing)
    return PaywallView {}.environment(vm)
}

#Preview("Nothing to restore") {
    let vm = FeedViewModel.mock(startingAt: .outOfSwipes)
    vm.previewWall(status: .nothingToRestore)
    return PaywallView {}.environment(vm)
}
#endif
