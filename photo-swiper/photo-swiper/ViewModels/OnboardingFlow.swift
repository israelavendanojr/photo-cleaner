import Foundation
import Observation

/// Where first-launch onboarding is, and whether it holds the screen while the first deck is dealt
/// underneath. `FeedViewModel` owns it and keeps `phase`: it asks `route(_:)` before entering a deck
/// phase, and applies what `finish()` hands back.
@Observable
@MainActor
final class OnboardingFlow {

    /// Photo access was granted from onboarding. The primer can't be left backward from here.
    private(set) var isOnboardingAccessGranted = false
    private(set) var onboardingStep = OnboardingStep.intro
    /// Onboarding will offer reminders after photo access. Re-checked when it gets there.
    private(set) var offersReminderStep = false
    /// Onboarding stays up after access is granted until its last step, while the deck is dealt underneath.
    private(set) var holdsOnboarding = false
    /// Where the deck stands while onboarding holds the screen. Becomes `phase` when onboarding finishes.
    private(set) var heldPhase: FeedPhase?
    /// Debug builds: this onboarding is a replay, so every step shows whatever was decided before.
    private var isReplayingOnboarding = false

    /// Holds whether onboarding is done.
    private let defaults: UserDefaults
    /// Nil where reminders can't be offered (tests, previews).
    private let notifier: RefillNotifier?
    private let library: any PhotoLibraryProviding

    init(defaults: UserDefaults, notifier: RefillNotifier?, library: any PhotoLibraryProviding) {
        self.defaults = defaults
        self.notifier = notifier
        self.library = library
    }

    /// Only before the user has been asked for photo access, unless a debug reset asked for it again.
    var needsOnboarding: Bool {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded) else { return false }
        // Set only by Developer mode's "Reset onboarding" (or debug builds' `-resetOnboarding`). Read
        // without asking Developer mode, whose environment check may not have answered this early.
        if defaults.bool(forKey: DefaultsKey.debugShowOnboarding) { return true }
        return library.needsAccessPrompt()
    }

    /// Onboarding will end on the unlock offer.
    func offersUpsellStep(isUnlocked: Bool) -> Bool { !isUnlocked || isReplayingOnboarding }

    /// Onboarding is opening at launch.
    func enter() {
        // Only Developer mode's "Reset onboarding" (or debug builds' `-resetOnboarding`) sets it.
        isReplayingOnboarding = defaults.bool(forKey: DefaultsKey.debugShowOnboarding)
    }

    /// Works out whether reminders will be offered after photo access.
    func settleReminderOffer() async {
        offersReminderStep = await reminderStepApplies()
    }

    /// Onboarding's Allow button was tapped.
    func markOnboarded() {
        // Written before access is asked for, so a relaunch from any later step opens the feed.
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        defaults.removeObject(forKey: DefaultsKey.debugShowOnboarding)
    }

    /// Photo access was granted from onboarding, which now holds the screen until its last step.
    func accessGranted() {
        isOnboardingAccessGranted = true
        holdsOnboarding = true
    }

    /// Moves onboarding past photo access to the next step that applies. True when none is left and it should finish.
    /// Each step is checked as it's reached, so e.g. a restore that lands meanwhile skips the offer.
    func advance(isUnlocked: () -> Bool) async -> Bool {
        if onboardingStep == .intro {
            // Once offered it stays, so coming back through after answering iOS still shows it.
            if !offersReminderStep { offersReminderStep = await reminderStepApplies() }
            if offersReminderStep {
                onboardingStep = .notifications
                return false
            }
        }
        if onboardingStep != .upsell, offersUpsellStep(isUnlocked: isUnlocked()) {
            onboardingStep = .upsell
            return false
        }
        return true
    }

    /// There's a step after photo access to go back from. `FeedViewModel` adds the phase and purchase checks.
    var canGoBack: Bool { holdsOnboarding && onboardingStep != .intro }

    /// Back one step after photo access: the offer to reminders where they were shown, either to the primer.
    func goBack() {
        onboardingStep = onboardingStep == .upsell && offersReminderStep ? .notifications : .intro
    }

    /// Lets the feed replace onboarding. Returns the deck's held phase to apply, or nil if the first
    /// deck is still being built, in which case `route(_:)` passes it straight through once it's ready.
    func finish() -> FeedPhase? {
        guard holdsOnboarding else { return nil }
        holdsOnboarding = false
        isReplayingOnboarding = false
        guard let held = heldPhase else { return nil }
        heldPhase = nil
        return held
    }

    /// Holds the deck's next phase while onboarding is still up. Otherwise returns it, for `phase`.
    func route(_ next: FeedPhase) -> FeedPhase? {
        guard holdsOnboarding else { return next }
        heldPhase = next
        return nil
    }

    /// Reminders can be offered and the system hasn't asked yet, since iOS only asks once.
    /// A debug replay offers them regardless.
    private func reminderStepApplies() async -> Bool {
        guard let notifier else { return false }
        return isReplayingOnboarding ? true : await notifier.canAsk()
    }
}
