import Foundation

/// Decides which entitlement store the app runs on, alongside `LibraryServices`.
enum EntitlementServices {
    /// Mocks get a store that forgets on every launch and starts locked, so the paywall is
    /// reachable. In debug builds, `-unlocked YES|NO` sets the starting state for either, and
    /// `-restoreFails YES` makes Restore come back empty.
    @MainActor
    static func make(mock: Bool) -> any EntitlementStore {
        // TODO(storekit): Return the StoreKit store here for the real library.
        #if DEBUG
        var defaults = UserDefaults.standard
        if mock {
            let suite = "mock.entitlements"
            defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
        }
        let arguments = UserDefaults.standard
        if arguments.object(forKey: "unlocked") != nil {
            defaults.set(arguments.bool(forKey: "unlocked"), forKey: DefaultsKey.debugUnlocked)
        }
        return DebugEntitlementStore(defaults: defaults, restoreSucceeds: !arguments.bool(forKey: "restoreFails"))
        #else
        return DebugEntitlementStore()
        #endif
    }
}
