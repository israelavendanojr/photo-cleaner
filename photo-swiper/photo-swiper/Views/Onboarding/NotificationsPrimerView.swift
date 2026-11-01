import SwiftUI

/// Onboarding's reminders step: what a refill reminder looks like and when one can arrive, before
/// iOS asks. "Not now" never shows the system prompt, so it can still be asked from the wall or Settings.
/// Come back to after answering, it says how things stand and just continues.
struct NotificationsPrimerView: View {
    private enum Answer { case unasked, on, off }

    @Environment(FeedViewModel.self) private var vm
    /// Called once the user has answered, or skipped.
    let onContinue: () -> Void

    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotificationBannerPreview(message: Copy.bannerBody(vm.allowanceTunables))
                .onboardingEntrance(order: 0)
            Text(Copy.headline)
                .dsSerif(40, relativeTo: .largeTitle, weight: .medium)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, DS.Spacing.xl)
                .onboardingEntrance(order: 1)
            caption
                .padding(.top, DS.Spacing.m)
                .onboardingEntrance(order: 2)
        }
        .onboardingLayout(footerOrder: 3) {
            VStack(spacing: DS.Spacing.s) {
                if answer == .unasked {
                    askButtons
                } else {
                    Button(Copy.continueTitle) {
                        Haptics.advance()
                        onContinue()
                    }
                    .buttonStyle(.pill(.ink))
                    .accessibilityIdentifier("onboarding.notifications.continue")
                }
            }
        }
    }

    /// How the user answered iOS, if they have. Holds while the prompt is up, so the screen doesn't
    /// change under it on the way out.
    private var answer: Answer {
        if isAsking { return .unasked }
        if vm.isRemindersOptedIn { return .on }
        return vm.areRemindersDenied ? .off : .unasked
    }

    @ViewBuilder
    private var caption: some View {
        switch answer {
        case .unasked:
            Text(Copy.caption)
                .font(.body)
                .foregroundStyle(DS.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .on, .off:
            let isOn = answer == .on
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Image(systemName: isOn ? "checkmark" : "bell.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? DS.Palette.brick : DS.Palette.secondary)
                    .accessibilityHidden(true)
                Text(isOn ? Copy.remindersOn : Copy.remindersOff)
                    .font(.body)
                    .foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var askButtons: some View {
        Button(action: turnOn) {
            ZStack {
                Text(Copy.turnOn)
                    .opacity(isAsking ? 0 : 1)
                if isAsking {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .buttonStyle(.pill(.ink))
        .allowsHitTesting(!isAsking)
        .accessibilityIdentifier("onboarding.notifications.enable")
        Button(Copy.notNow) {
            Haptics.advance()
            onContinue()
        }
        .buttonStyle(.pill(.ghost))
        .disabled(isAsking)
        .accessibilityIdentifier("onboarding.notifications.skip")
    }

    /// Shows the system prompt, then moves on whatever the answer. Stays asking as it leaves.
    private func turnOn() {
        Haptics.advance()
        isAsking = true
        Task {
            await vm.remindWhenSwipesAreBack()
            onContinue()
        }
    }
}

/// This screen's words, together so they're easy to change. Numbers come from the reminder rules.
private enum Copy {
    static let headline = "Know when your swipes are back."
    static let turnOn = "Turn On Reminders"
    static let notNow = "Not now"
    static let continueTitle = "Continue"
    static let remindersOn = "Reminders are on. We'll let you know when your swipes are back."
    static let remindersOff = "Notifications are off. You can turn them on any time in Settings."

    /// "Only after you run out of swipes. At most two a day, and never between 9 PM and 9 AM."
    static var caption: String {
        let perDay = Format.spelled(RefillReminderPlanner.maxPerDay)
        let quietStart = hour(RefillReminderPlanner.quietStartHour)
        let quietEnd = hour(RefillReminderPlanner.quietEndHour)
        return "Only after you run out of swipes. At most \(perDay) a day, and never between \(quietStart) and \(quietEnd)."
    }

    /// The real reminder's wording, e.g. "10 swipes are back".
    static func bannerBody(_ tunables: SwipeAllowance.Tunables) -> String {
        RefillReminderPlanner.refillBody(amount: tunables.refillAmount, estimate: nil)
    }

    /// "9 PM", in the user's own clock style.
    private static func hour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// A stand-in for an iOS notification banner, sliding down from the top of its frame.
/// Fades in instead with Reduce Motion.
private struct NotificationBannerPreview: View {
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 38

    /// Waits for the screen's entrance, so the banner lands after its frame has appeared.
    private static let delay = 0.55

    var body: some View {
        banner
            .padding(DS.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, DS.Spacing.xxl)
            .background(DS.Palette.muted, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            // The banner comes in from beyond the top edge, like it does on screen.
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example notification from \(AppInfo.name): \(message)")
            .onAppear {
                guard !isShown else { return }
                let animation = reduceMotion
                    ? Animation.easeIn(duration: 0.3).delay(Self.delay)
                    : DS.Motion.calm.delay(Self.delay)
                withAnimation(animation) { isShown = true }
            }
    }

    private var banner: some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            appIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppInfo.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                    Spacer(minLength: DS.Spacing.xs)
                    Text("now")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.secondary)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: DS.Radius.inner - DS.Spacing.xxs, style: .continuous))
        .softShadow()
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : -120)
    }

    /// The asset catalog's app icon can't be drawn in a view, so this stands in for it.
    private var appIcon: some View {
        RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
            .fill(DS.Palette.ink)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: iconSize * 0.45, weight: .medium))
                    .foregroundStyle(DS.Palette.paper)
            }
    }
}

#if DEBUG
#Preview {
    NotificationsPrimerView(onContinue: {})
        .background(DS.Palette.paper)
        .environment(FeedViewModel.mock(startingAt: .onboarding))
}

#Preview("Reminders on") {
    let vm = FeedViewModel.mock(startingAt: .onboarding)
    return NotificationsPrimerView(onContinue: {})
        .background(DS.Palette.paper)
        .environment(vm)
        .task { await vm.remindWhenSwipesAreBack() }
}

#Preview("Banner") {
    NotificationBannerPreview(message: "10 swipes are back")
        .padding()
        .background(DS.Palette.paper)
}
#endif
