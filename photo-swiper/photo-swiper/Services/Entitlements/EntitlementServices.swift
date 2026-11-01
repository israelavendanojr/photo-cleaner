import Foundation

/// Decides which entitlement store the app runs on, alongside `LibraryServices`.
enum EntitlementServices {
    /// The real library gets StoreKit. Mocks get a store that forgets on every launch and starts
    /// locked, so the paywall is reachable.
    ///
    /// Debug builds wrap StoreKit in Settings' unlock override, and `-unlocked YES|NO` sets it
    /// (saved, so it outlives the launch). For mocks, `-unlocked YES|NO` sets the starting state
    /// and `-restoreFails YES` makes Restore come back empty.
    @MainActor
    static func make(mock: Bool) -> any EntitlementStore {
        #if DEBUG
        let arguments = UserDefaults.standard
        guard mock else {
            let store = DebugOverrideEntitlementStore(base: StoreKitEntitlementStore())
            if arguments.object(forKey: "unlocked") != nil {
                store.setOverride(arguments.bool(forKey: "unlocked") ? .unlocked : .locked)
            }
            return store
        }
        let suite = "mock.entitlements"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        if arguments.object(forKey: "unlocked") != nil {
            defaults.set(arguments.bool(forKey: "unlocked"), forKey: DefaultsKey.debugUnlocked)
        }
        return DebugEntitlementStore(defaults: defaults, restoreSucceeds: !arguments.bool(forKey: "restoreFails"))
        #else
        return mock ? DebugEntitlementStore() : StoreKitEntitlementStore()
        #endif
    }
}
