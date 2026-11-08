import Foundation
import Observation

/// Refill reminders and the clutter estimate they quote. `FeedViewModel` owns it and passes in
/// the allowance and the deck ahead, read fresh where an await could have changed them.
@Observable
@MainActor
final class ReminderController {
    /// The allowance as reminders see it.
    struct AllowanceState {
        let allowance: SwipeAllowance
        let tunables: SwipeAllowance.Tunables
        let isUnlocked: Bool
    }

    /// What's left to clear, worked out when the wall opens.
    private(set) var clutterEstimate: ClutterEstimate?
    /// The user tapped "Remind me" and the system said yes.
    private(set) var isRemindersOptedIn = false
    /// Notifications are turned off for the app, found on asking or by Settings checking.
    private(set) var areRemindersDenied = false

    /// Nil where reminders can't be offered (tests, previews).
    private let notifier: RefillNotifier?
    private let builder: any FeedBuilding
    private let store: any ProgressStoring
    private let now: () -> Date

    init(notifier: RefillNotifier?, builder: any FeedBuilding, store: any ProgressStoring, now: @escaping () -> Date) {
        self.notifier = notifier
        self.builder = builder
        self.store = store
        self.now = now
        isRemindersOptedIn = notifier?.isOptedIn ?? false
    }

    /// "Remind me when swipes are back" can be offered.
    var canRemind: Bool { notifier != nil }

    /// Days of free swipes it would take to get through the likely clears.
    func daysToFinish(swipesPerDay: Double) -> Double? {
        clutterEstimate?.daysToFinish(swipesPerDay: swipesPerDay)
    }

    /// "Remind me when swipes are back". Asks for notification permission, then schedules if already out.
    func remindWhenSwipesAreBack(state: () -> AllowanceState, similarAhead: () -> Int) async {
        guard let notifier else { return }
        isRemindersOptedIn = await notifier.optIn()
        areRemindersDenied = !isRemindersOptedIn
        if isRemindersOptedIn, state().allowance.remaining == 0 { await scheduleReminders(state: state, similarAhead: similarAhead) }
    }

    /// The Settings switch. On asks for permission the same way the wall does; off cancels what's scheduled.
    func setRemindersEnabled(_ on: Bool, state: () -> AllowanceState, similarAhead: () -> Int) async {
        guard let notifier else { return }
        if on {
            await remindWhenSwipesAreBack(state: state, similarAhead: similarAhead)
        } else {
            notifier.optOut(now: now())
            isRemindersOptedIn = false
        }
    }

    /// Reads whether notifications are off in the Settings app, which can change while the app is away.
    func refreshReminderPermission() async {
        guard let notifier else { return }
        areRemindersDenied = await notifier.isDenied()
    }

    /// Back and swiping, or unlocked: scheduled reminders are no longer needed.
    func cancelAll() {
        notifier?.cancelAll(now: now())
    }

    func scheduleReminders(state: () -> AllowanceState, similarAhead: () -> Int) async {
        let before = state()
        guard let notifier, !before.isUnlocked, let next = before.allowance.nextRefillAt(before.tunables) else { return }
        if clutterEstimate == nil { await refreshEstimate(similarAhead: similarAhead) }
        let current = state()
        await notifier.scheduleOnEmpty(
            nextRefillAt: next,
            fullAt: current.allowance.fullAt(current.tunables),
            tunables: current.tunables,
            estimate: clutterEstimate,
            now: now()
        )
    }

    /// - Parameter similarAhead: Similar sets still ahead in the deck, read once the estimate is back.
    func refreshEstimate(similarAhead: () -> Int) async {
        guard var estimate = await builder.clutterEstimate(excluding: store.excludedFromNewSession(asOf: now()), now: now()) else { return }
        // Similar sets still ahead in the deck count too.
        estimate.similarGroupCount += similarAhead()
        clutterEstimate = estimate
    }
}
