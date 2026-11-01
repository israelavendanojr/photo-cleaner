import Foundation

/// Decides which entitlement store the app runs on, alongside `LibraryServices`.
enum EntitlementServices {
    /// The real library gets StoreKit. Mocks get a store that forgets on every launch and starts
    /// locked, so the paywall is reachable. In debug builds, `-unlocked YES|NO` sets the mock's
    /// starting state, and `-restoreFails YES` makes the mock's Restore come back empty.
    @MainActor
    static func make(mock: Bool) -> any EntitlementStore {
        #if DEBUG
        guard mock else { return StoreKitEntitlementStore() }
        let suite = "mock.entitlements"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let arguments = UserDefaults.standard
        if arguments.object(forKey: "unlocked") != nil {
            defaults.set(arguments.bool(forKey: "unlocked"), forKey: DefaultsKey.debugUnlocked)
        }
        return DebugEntitlementStore(defaults: defaults, restoreSucceeds: !arguments.bool(forKey: "restoreFails"))
        #else
        return mock ? DebugEntitlementStore() : StoreKitEntitlementStore()
        #endif
    }
}
