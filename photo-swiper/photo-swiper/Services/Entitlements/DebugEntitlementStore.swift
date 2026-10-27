import Foundation
import Observation
import os

// TODO(storekit): Replace this whole type with a StoreKit 2 store: load the product for
// `displayPrice`, `Product.purchase()` in `unlock()`, `AppStore.sync()` plus
// `Transaction.currentEntitlements` in `restore()` (a thrown sync is `.failed`, no entitlement is
// `.nothingToRestore`), and listen to `Transaction.updates`.
// Then pick it in `EntitlementServices.make(mock:)`.

/// Stand-in purchases. Debug builds unlock after a short pause, so the loading states can be
/// seen, and remember it in `UserDefaults`.
///
/// Release builds never unlock: `isUnlocked` is always false and `unlock()`/`restore()` fail
/// with a log line, so a build can't ship with a free unlock.
@Observable
@MainActor
final class DebugEntitlementStore: EntitlementStore {
    private static let log = Logger(subsystem: "com.israelavendanojr.photo-swiper", category: "entitlement")

    private(set) var isUnlocked: Bool
    let displayPrice = "$12.99"

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

    func unlock() async -> Bool {
        try? await Task.sleep(for: delay)
        #if DEBUG
        grant()
        return true
        #else
        Self.log.error("Unlock requested, but purchases aren't wired up yet. Not unlocking.")
        return false
        #endif
    }

    func restore() async -> RestoreOutcome {
        try? await Task.sleep(for: delay)
        #if DEBUG
        guard restoreSucceeds else { return .nothingToRestore }
        grant()
        return .restored
        #else
        Self.log.error("Restore requested, but purchases aren't wired up yet. Nothing restored.")
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
