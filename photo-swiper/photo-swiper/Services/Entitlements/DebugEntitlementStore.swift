import Foundation
import Observation
import os

/// Stand-in purchases for the mock library and previews. Debug builds unlock after a short pause,
/// so the loading states can be seen, and remember it in `UserDefaults`.
///
/// Release builds never unlock: `isUnlocked` is always false and `unlock()`/`restore()` fail
/// with a log line, so a build can't ship with a free unlock.
@Observable
@MainActor
final class DebugEntitlementStore: EntitlementStore {
    private static let log = Logger.app(category: "entitlement")

    private(set) var isUnlocked: Bool
    let displayPrice = "$9.99"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let delay: Duration
    /// Lets "Nothing to restore" be seen in debug builds.
    @ObservationIgnored private let restoreSucceeds: Bool

    init(defaults: UserDefaults = .standard, delay: Duration = .seconds(1.2), restoreSucceeds: Bool = true) {
        self.defaults = defaults
        self.delay = delay
        self.restoreSucceeds = restoreSucceeds
        #if DEBUG
        isUnlocked = defaults.bool(forKey: DefaultsKey.debugUnlocked)
        #else
        isUnlocked = false
        #endif
    }

    func unlock() async -> PurchaseOutcome {
        try? await Task.sleep(for: delay)
        #if DEBUG
        grant()
        return .purchased
        #else
        Self.log.error("Unlock requested from the stand-in store. Not unlocking.")
        return .failed
        #endif
    }

    func restore() async -> RestoreOutcome {
        try? await Task.sleep(for: delay)
        #if DEBUG
        guard restoreSucceeds else { return .nothingToRestore }
        grant()
        return .restored
        #else
        Self.log.error("Restore requested from the stand-in store. Nothing restored.")
        return .failed
        #endif
    }

    #if DEBUG
    /// Settings' debug toggle.
    func setUnlocked(_ unlocked: Bool) {
        isUnlocked = unlocked
        defaults.set(unlocked, forKey: DefaultsKey.debugUnlocked)
    }

    private func grant() {
        setUnlocked(true)
    }
    #endif
}
