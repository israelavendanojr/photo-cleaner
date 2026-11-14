import Foundation
import Testing
@testable import photo_swiper

/// Developer mode's compression levels (JUN-50): each setting maps onto `CompressionLevels`, overrides are
/// saved and apply only while Developer mode is on, and the viewer and exports read them through the
/// view model.
@MainActor
struct CompressionTunablesTests {
    private func tunables(defaults: UserDefaults, devMode: DistributionEnvironment = .debug) -> CompressionTunables {
        CompressionTunables(defaults: defaults, devMode: DevMode(environment: devMode, defaults: defaults))
    }

    @Test func theDefaultsAreTheSpecsStartingPoints() {
        let compression = tunables(defaults: freshDefaults())
        #expect(compression.value(.lightBitratePercent) == 60)
        #expect(compression.value(.balancedLongEdge) == 1920)
        #expect(compression.value(.balancedKbps) == 6000)
        #expect(compression.value(.maxLongEdge) == 1280)
        #expect(compression.value(.maxKbps) == 2500)
        #expect(compression.value(.audioKbps) == 128)
        #expect(compression.value(.alreadySmallPercent) == 10)
        #expect(compression.levels == .standard)
        #expect(!compression.isCustomized)
    }

    @Test func anOverrideChangesTheLevelsAndIsRemembered() {
        let defaults = freshDefaults()
        let compression = tunables(defaults: defaults)

        compression.set(.balancedKbps, 4000)
        compression.set(.maxLongEdge, 960)
        compression.set(.lightBitratePercent, 75)

        #expect(compression.levels.balanced.videoBitrate == .fixed(4_000_000))
        #expect(compression.levels.max.maxLongEdge == 960)
        #expect(compression.levels.light.videoBitrate == .fractionOfSource(0.75))
        #expect(compression.isCustomized)
        #expect(tunables(defaults: defaults).levels.max.maxLongEdge == 960, "Remembered across launches")
    }

    @Test func valuesAreClampedAndTheDefaultClearsTheOverride() {
        let compression = tunables(defaults: freshDefaults())
        compression.set(.audioKbps, 10_000)
        #expect(compression.value(.audioKbps) == 320)

        compression.set(.audioKbps, 128)
        #expect(!compression.isCustomized)
    }

    @Test func overridesApplyOnlyInDeveloperMode() {
        let defaults = freshDefaults()
        tunables(defaults: defaults).set(.maxKbps, 1000)

        let appStore = tunables(defaults: defaults, devMode: .production)
        #expect(appStore.levels == .standard)
    }

    @Test func theViewerAndExportsUseTheLiveLevels() {
        let compression = tunables(defaults: freshDefaults())
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(),
                               defaults: freshDefaults(), compression: compression)
        compression.set(.maxLongEdge, 720)
        #expect(vm.videoEditOptions.levels.max.maxLongEdge == 720)
    }
}
