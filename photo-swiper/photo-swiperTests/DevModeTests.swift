import Foundation
import StoreKit
import Testing
@testable import photo_swiper

/// Developer mode: where it exists, the hidden switch, and that App Store builds can never use the
/// unlock override or tuned limits.
@MainActor
struct DevModeTests {
    private func devMode(_ environment: DistributionEnvironment, defaults: UserDefaults = freshDefaults()) -> DevMode {
        DevMode(environment: environment, defaults: defaults)
    }

    private func tap(_ devMode: DevMode, times: Int, start: Date = .now) -> [String?] {
        (0..<times).map { devMode.registerVersionTap(at: start.addingTimeInterval(Double($0) * 0.2)) }
    }

    // MARK: Environment

    @Test func appTransactionEnvironmentsMap() {
        #expect(DistributionEnvironment.from(.sandbox) == .testFlight)
        #expect(DistributionEnvironment.from(.xcode) == .xcode)
        #expect(DistributionEnvironment.from(.production) == .production)
    }

    @Test func debugBuildsAssumeDebug() async {
        #if DEBUG
        #expect(DistributionEnvironment.assumed == .debug)
        #expect(await DistributionEnvironment.resolve() == .debug)
        #else
        #expect(DistributionEnvironment.assumed == .production)
        #endif
    }

    @Test func debugStartsOnAndCanBeSwitchedOff() {
        let defaults = freshDefaults()
        let devMode = devMode(.debug, defaults: defaults)
        #expect(devMode.isAvailable)
        #expect(devMode.isEnabled)

        devMode.setEnabled(false)
        #expect(!devMode.isEnabled)
        #expect(!self.devMode(.debug, defaults: defaults).isEnabled, "Remembered across launches")
    }

    @Test func testFlightStartsOffAndSevenTapsToggleIt() {
        let devMode = devMode(.testFlight)
        #expect(devMode.isAvailable)
        #expect(!devMode.isEnabled)

        let toasts = tap(devMode, times: DevMode.tapsToToggle)
        #expect(toasts.dropLast().allSatisfy { $0 == nil })
        #expect(toasts.last == "Developer mode on")
        #expect(devMode.isEnabled)

        #expect(tap(devMode, times: DevMode.tapsToToggle).last == "Developer mode off")
        #expect(!devMode.isEnabled)
    }

    @Test func slowTapsStartTheCountAgain() {
        let devMode = devMode(.testFlight)
        let start = Date.now
        _ = tap(devMode, times: DevMode.tapsToToggle - 1, start: start)
        let late = start.addingTimeInterval(60)
        #expect(devMode.registerVersionTap(at: late) == nil)
        #expect(!devMode.isEnabled)
    }

    // MARK: App Store builds

    @Test func productionNeverHasDeveloperMode() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: DefaultsKey.devModeEnabled)
        let devMode = devMode(.production, defaults: defaults)

        #expect(!devMode.isAvailable)
        #expect(!devMode.isEnabled, "A saved switch from TestFlight is ignored")
        #expect(tap(devMode, times: DevMode.tapsToToggle * 2).allSatisfy { $0 == nil })
        devMode.setEnabled(true)
        #expect(!devMode.isEnabled)
    }

    @Test func theUnlockOverrideIsImpossibleInAppStoreBuilds() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: DefaultsKey.devModeEnabled)
        defaults.set(UnlockOverride.unlocked.rawValue, forKey: DefaultsKey.debugUnlockOverride)
        let devMode = devMode(.production, defaults: defaults)
        let base = StoreKitEntitlementStore(defaults: defaults, sync: {})
        let store = DebugOverrideEntitlementStore(base: base, defaults: defaults, devMode: devMode)

        #expect(store.override == .unlocked)
        #expect(!store.isUnlocked, "Production answers with StoreKit alone")
        store.setOverride(.unlocked)
        #expect(!store.isUnlocked)
    }

    @Test func theUnlockOverrideNeedsDeveloperModeInTestFlight() {
        let defaults = freshDefaults()
        let devMode = devMode(.testFlight, defaults: defaults)
        let base = StoreKitEntitlementStore(defaults: defaults, sync: {})
        let store = DebugOverrideEntitlementStore(base: base, defaults: defaults, devMode: devMode)
        store.setOverride(.unlocked)
        #expect(!store.isUnlocked, "Not before the taps")

        _ = tap(devMode, times: DevMode.tapsToToggle)
        #expect(store.isUnlocked)

        devMode.setEnabled(false)
        #expect(!store.isUnlocked)
    }

    @Test func productionIgnoresTunedLimits() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: DefaultsKey.devModeEnabled)
        defaults.set(5, forKey: FreeTierTunable.swipeCap.defaultsKey)
        defaults.set(10, forKey: FreeTierTunable.freeBinMB.defaultsKey)
        let tier = FreeTierTunables(defaults: defaults, devMode: devMode(.production, defaults: defaults))

        #expect(tier.limits == .standard)
    }
}
