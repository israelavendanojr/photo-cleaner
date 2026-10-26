import Foundation
import UserNotifications

/// The bits of `UNUserNotificationCenter` the reminders use, so tests can fake it.
@MainActor
protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func add(_ reminder: RefillReminder) async
    func removePending(_ ids: [String])
}

/// One local notification, before it becomes a `UNNotificationRequest`.
struct RefillReminder: Equatable, Sendable {
    /// The refill after hitting zero, then the balance back at the cap.
    static let nextID = "refill.next"
    static let fullID = "refill.full"
    static let allIDs = [nextID, fullID]

    let id: String
    let fireAt: Date
    let body: String
}

/// When and what to remind. Pure, so tests pin it with fixed dates and calendars.
enum RefillReminderPlanner {
    /// Nothing lands between 9 PM and 9 AM local time.
    static let quietStartHour = 21
    static let quietEndHour = 9
    static let maxPerDay = 2

    /// `date`, or the next 9 AM if it falls in quiet hours.
    static func outsideQuietHours(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= quietStartHour || hour < quietEndHour else { return date }
        let day = hour >= quietStartHour ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
        return calendar.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: day) ?? date
    }

    /// "10 swipes are back · 3 sets of similar shots waiting", falling back to bytes, then plain.
    static func refillBody(amount: Int, estimate: ClutterEstimate?) -> String {
        let lead = "\(amount) swipes are back"
        if let groups = estimate?.similarGroupCount, groups > 0 {
            return "\(lead) · \(groups) \(groups == 1 ? "set" : "sets") of similar shots waiting"
        }
        if let bytes = estimate?.likelyClearBytes, bytes > 0 {
            return "\(lead) · about \(Format.size(bytes)) to clear"
        }
        return lead
    }

    /// The reminders to schedule on hitting zero: the next refill, and the balance back at the cap
    /// in case the user hasn't returned by then. Each moves out of quiet hours. When both would land at
    /// the same time, only the full one is kept, and no day gets more than `maxPerDay` counting `log`,
    /// the fire dates already scheduled.
    static func plan(
        nextRefillAt: Date,
        fullAt: Date?,
        tunables: SwipeAllowance.Tunables,
        estimate: ClutterEstimate?,
        log: [Date],
        calendar: Calendar
    ) -> [RefillReminder] {
        var candidates = [RefillReminder(
            id: RefillReminder.nextID,
            fireAt: outsideQuietHours(nextRefillAt, calendar: calendar),
            body: refillBody(amount: tunables.refillAmount, estimate: estimate)
        )]
        if let fullAt, fullAt > nextRefillAt {
            let full = RefillReminder(
                id: RefillReminder.fullID,
                fireAt: outsideQuietHours(fullAt, calendar: calendar),
                body: "Your \(tunables.cap) swipes are ready"
            )
            if full.fireAt == candidates[0].fireAt { candidates = [] }
            candidates.append(full)
        }

        var scheduled = log
        return candidates.filter { reminder in
            let sameDay = scheduled.filter { calendar.isDate($0, inSameDayAs: reminder.fireAt) }.count
            guard sameDay < maxPerDay else { return false }
            scheduled.append(reminder.fireAt)
            return true
        }
    }
}

/// Local "your swipes are back" reminders. Only asks for permission when the user taps "Remind me",
/// and only schedules once they've opted in.
@MainActor
final class RefillNotifier {
    private let center: any NotificationScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(center: any NotificationScheduling, defaults: UserDefaults, calendar: Calendar = .current) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Read by Settings too.
    var isOptedIn: Bool {
        get { defaults.bool(forKey: DefaultsKey.refillRemindersOptIn) }
        set { defaults.set(newValue, forKey: DefaultsKey.refillRemindersOptIn) }
    }

    /// Asks for permission. Opted in only if it was granted.
    func optIn() async -> Bool {
        let granted = await center.requestAuthorization()
        isOptedIn = granted
        return granted
    }

    /// Schedules the reminders for an empty allowance. Fixed identifiers, so calling it again replaces
    /// them instead of adding more.
    func scheduleOnEmpty(
        nextRefillAt: Date,
        fullAt: Date?,
        tunables: SwipeAllowance.Tunables,
        estimate: ClutterEstimate?,
        now: Date
    ) async {
        guard isOptedIn else { return }
        cancelAll(now: now)
        let reminders = RefillReminderPlanner.plan(
            nextRefillAt: nextRefillAt, fullAt: fullAt, tunables: tunables,
            estimate: estimate, log: log(now: now), calendar: calendar
        )
        // Logged before the awaits, so a second call right after counts these.
        setLog(log(now: now) + reminders.map(\.fireAt))
        for reminder in reminders { await center.add(reminder) }
    }

    /// The user came back and swiped, or unlocked. Anything not yet fired no longer counts toward the cap.
    func cancelAll(now: Date) {
        center.removePending(RefillReminder.allIDs)
        setLog(log(now: now).filter { $0 <= now })
    }

    /// Fire dates from the last two days.
    private func log(now: Date) -> [Date] {
        let dates = (defaults.array(forKey: DefaultsKey.refillReminderLog) as? [Date]) ?? []
        return dates.filter { $0 > now.addingTimeInterval(-2 * 86_400) }
    }

    private func setLog(_ dates: [Date]) {
        defaults.set(dates, forKey: DefaultsKey.refillReminderLog)
    }
}

/// The real notification center.
@MainActor
final class SystemNotificationCenter: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ reminder: RefillReminder) async {
        let content = UNMutableNotificationContent()
        content.body = reminder.body
        content.sound = .default
        let interval = max(1, reminder.fireAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    func removePending(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
