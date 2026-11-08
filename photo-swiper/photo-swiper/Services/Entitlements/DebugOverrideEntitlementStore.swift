import Foundation
import Observation

extension DefaultsKey {
    /// Developer mode only: an `UnlockOverride` over the StoreKit unlock.
    static let debugUnlockOverride = "debugUnlockOverride"
}

/// Developer mode's unlock switch over the real store.
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

/// The StoreKit store with Developer mode's override on top, remembered across launches.
/// Purchases and restores still go through StoreKit; only `isUnlocked` is overridden.
///
/// The override counts only while `devMode.isEnabled`, checked on every read. App Store builds
/// never enable Developer mode, so there `isUnlocked` is always StoreKit's answer.
@Observable
@MainActor
final class DebugOverrideEntitlementStore: EntitlementStore {
    let base: StoreKitEntitlementStore
    private(set) var override: UnlockOverride
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let devMode: DevMode

    init(base: StoreKitEntitlementStore, defaults: UserDefaults = .standard, devMode: DevMode? = nil) {
        self.base = base
        self.defaults = defaults
        self.devMode = devMode ?? .shared
        override = defaults.string(forKey: DefaultsKey.debugUnlockOverride).flatMap(UnlockOverride.init) ?? .off
    }

    var isUnlocked: Bool {
        guard devMode.isEnabled else { return base.isUnlocked }
        return switch override {
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
