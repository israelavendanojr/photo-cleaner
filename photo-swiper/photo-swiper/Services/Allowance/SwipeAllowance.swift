import Foundation

/// Free swipes, refilled over time like energy in a game.
///
/// Every card decision spends one. Below the cap a refill timer runs: each `refillInterval` adds
/// `refillAmount`, clamped to the cap, and the timer stops once the cap is reached. Nothing ticks in
/// the background; `settle(at:)` works out what's owed from the stored anchor and the time it's given,
/// so time away from the app is credited in full. Pure and clock-free, so tests pin it to fixed dates.
/// The unlock bypasses all of this in `FeedViewModel`.
struct SwipeAllowance: Codable, Equatable, Sendable {
    struct Tunables: Equatable, Sendable {
        var cap = 20
        var refillAmount = 10
        var refillInterval: TimeInterval = 6 * 60 * 60

        static let standard = Tunables()
        /// Debug builds' `-refillSoon YES`: refills every minute, to watch the countdown and reminders.
        static let refillSoon = Tunables(refillInterval: 60)

        /// Free swipes a day when every refill is taken, e.g. 40.
        var swipesPerDay: Double { Double(refillAmount) * 86_400 / refillInterval }
    }

    private(set) var balance: Int
    /// When the running refill timer started. Nil at the cap, where no timer runs.
    private(set) var anchor: Date?
    /// The latest time seen. A clock set back before it grants nothing.
    private(set) var lastSeen: Date

    /// Starts full.
    init(tunables: Tunables = .standard, now: Date) {
        balance = tunables.cap
        anchor = nil
        lastSeen = now
    }

    /// Debug builds' `-swipesLeft N`: a balance with its timer starting now.
    init(balance: Int, tunables: Tunables = .standard, now: Date) {
        self.balance = min(max(balance, 0), tunables.cap)
        anchor = self.balance < tunables.cap ? now : nil
        lastSeen = now
    }

    var remaining: Int { balance }

    func nextRefillAt(_ t: Tunables) -> Date? {
        anchor.map { $0.addingTimeInterval(t.refillInterval) }
    }

    /// Refills still to come before the cap.
    func refillsToFull(_ t: Tunables) -> Int {
        let missing = max(0, t.cap - balance)
        return (missing + t.refillAmount - 1) / t.refillAmount
    }

    /// When the balance reaches the cap if nothing more is spent. Nil when already full.
    func fullAt(_ t: Tunables) -> Date? {
        anchor.map { $0.addingTimeInterval(t.refillInterval * Double(refillsToFull(t))) }
    }

    /// Credits every refill owed by `now`. Returns true if the balance went up.
    @discardableResult
    mutating func settle(at now: Date, _ t: Tunables) -> Bool {
        // The clock went backwards (or was set back): grant nothing until it catches up.
        guard now >= lastSeen else { return false }
        lastSeen = now
        guard let start = anchor else { return false }
        // Absolute intervals, so daylight saving changes neither shorten nor stretch a refill.
        let refills = Int(now.timeIntervalSince(start) / t.refillInterval)
        guard refills > 0 else { return false }
        let before = balance
        balance = min(t.cap, balance + refills * t.refillAmount)
        // At the cap the timer stops; below it the next one starts where the last one ended.
        anchor = balance >= t.cap ? nil : start.addingTimeInterval(Double(refills) * t.refillInterval)
        return balance > before
    }

    /// Spends one swipe. False, and nothing changes, when none are left.
    mutating func spend(at now: Date, _ t: Tunables) -> Bool {
        settle(at: now, t)
        guard balance > 0 else { return false }
        balance -= 1
        if anchor == nil, balance < t.cap { anchor = max(now, lastSeen) }
        return true
    }

    /// Gives back a swipe (undo), up to the cap.
    mutating func refund(at now: Date, _ t: Tunables) {
        settle(at: now, t)
        balance = min(t.cap, balance + 1)
        if balance >= t.cap { anchor = nil }
    }
}

/// Saves the allowance across launches. Without `defaults` it only lives in memory (tests, previews).
@MainActor
final class SwipeAllowanceStore {
    private let defaults: UserDefaults?
    private var memory: SwipeAllowance?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
    }

    /// In memory, starting from `initial` (full when nil).
    init(initial: SwipeAllowance?) {
        defaults = nil
        memory = initial
    }

    func load() -> SwipeAllowance? {
        guard let defaults else { return memory }
        guard let data = defaults.data(forKey: DefaultsKey.swipeAllowance) else { return nil }
        return try? JSONDecoder().decode(SwipeAllowance.self, from: data)
    }

    func save(_ allowance: SwipeAllowance) {
        guard let defaults else {
            memory = allowance
            return
        }
        if let data = try? JSONEncoder().encode(allowance) {
            defaults.set(data, forKey: DefaultsKey.swipeAllowance)
        }
    }
}
