#if DEBUG
import Foundation
import Observation

extension DefaultsKey {
    /// Debug builds only: an `UnlockOverride` over the StoreKit unlock. Release builds don't have it.
    static let debugUnlockOverride = "debugUnlockOverride"
}

/// Debug builds only: Settings' unlock switch over the real store.
enum UnlockOverride: String, CaseIterable, Identifiable {
    /// Whatever StoreKit says.
    case off
    case unlocked
    case locked

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off (StoreKit)"
        case .unlocked: "Forced unlocked"
        case .locked: "Forced locked"
        }
    }
}

/// Debug builds only: the StoreKit store with an override on top, remembered across launches.
/// Purchases and restores still go through StoreKit; only `isUnlocked` is overridden.
@Observable
@MainActor
final class DebugOverrideEntitlementStore: EntitlementStore {
    let base: StoreKitEntitlementStore
    private(set) var override: UnlockOverride
    @ObservationIgnored private let defaults: UserDefaults

    init(base: StoreKitEntitlementStore, defaults: UserDefaults = .standard) {
        self.base = base
        self.defaults = defaults
        override = defaults.string(forKey: DefaultsKey.debugUnlockOverride).flatMap(UnlockOverride.init) ?? .off
    }

    var isUnlocked: Bool {
        switch override {
        case .off: base.isUnlocked
        case .unlocked: true
        case .locked: false
        }
    }

    var displayPrice: String { base.displayPrice }

    func unlock() async -> PurchaseOutcome { await base.unlock() }

    func restore() async -> RestoreOutcome { await base.restore() }

    func setOverride(_ override: UnlockOverride) {
        self.override = override
        defaults.set(override.rawValue, forKey: DefaultsKey.debugUnlockOverride)
    }
}
#endif
