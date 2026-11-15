import Foundation
import Testing
@testable import photo_swiper

/// Developer mode's feature availability: who gets each bundle card, and that a bundle a user
/// doesn't get turns into single cards instead of going missing.
@MainActor
struct FeatureAvailabilityTests {
    private func tunables(defaults: UserDefaults, devMode: DistributionEnvironment = .debug) -> FeatureAvailabilityTunables {
        FeatureAvailabilityTunables(defaults: defaults, devMode: DevMode(environment: devMode, defaults: defaults))
    }

    // MARK: Availability

    @Test func eachAvailabilityAllowsTheRightTier() {
        #expect(FeatureAvailability.universal.allows(isUnlocked: false))
        #expect(FeatureAvailability.universal.allows(isUnlocked: true))
        #expect(!FeatureAvailability.paidOnly.allows(isUnlocked: false))
        #expect(FeatureAvailability.paidOnly.allows(isUnlocked: true))
        #expect(FeatureAvailability.freeOnly.allows(isUnlocked: false))
        #expect(!FeatureAvailability.freeOnly.allows(isUnlocked: true))
        #expect(!FeatureAvailability.off.allows(isUnlocked: false))
        #expect(!FeatureAvailability.off.allows(isUnlocked: true))
    }

    // MARK: Tunables

    @Test func everyoneGetsEveryFeatureByDefault() {
        let features = tunables(defaults: freshDefaults())
        #expect(TierFeature.allCases.allSatisfy { features.availability($0) == .universal })
        #expect(features.enabled(isUnlocked: false) == Set(TierFeature.allCases))
        #expect(features.enabled(isUnlocked: true) == Set(TierFeature.allCases))
        #expect(!features.isCustomized)
    }

    @Test func anOverrideIsSavedAndApplies() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.similarShots, .paidOnly)
        features.set(.duplicates, .freeOnly)

        let video: Set<TierFeature> = [.videoTrimmer, .videoCompression]
        #expect(features.enabled(isUnlocked: false) == Set<TierFeature>([.duplicates, .screenshotBatches]).union(video))
        #expect(features.enabled(isUnlocked: true) == Set<TierFeature>([.similarShots, .screenshotBatches]).union(video))
        #expect(features.isCustomized)
        #expect(tunables(defaults: defaults).availability(.similarShots) == .paidOnly, "Remembered across launches")
    }

    @Test func settingTheDefaultClearsTheOverride() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.screenshotBatches, .paidOnly)
        features.set(.screenshotBatches, .universal)

        #expect(!features.isCustomized)
        #expect(defaults.string(forKey: TierFeature.screenshotBatches.defaultsKey) == nil)
    }

    @Test func overridesAreIgnoredWithDeveloperModeOff() {
        let defaults = freshDefaults()
        tunables(defaults: defaults).set(.similarShots, .paidOnly)

        let features = tunables(defaults: defaults, devMode: .production)
        #expect(features.availability(.similarShots) == .universal)
        #expect(features.enabled(isUnlocked: false) == Set(TierFeature.allCases))
    }

    @Test func resetForgetsEveryOverride() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.similarShots, .paidOnly)
        features.set(.duplicates, .paidOnly)
        features.resetToDefaults()

        #expect(!features.isCustomized)
        #expect(!tunables(defaults: defaults).isCustomized)
    }

    // MARK: Unbundling

    @Test func eachBundleNeedsItsFeature() {
        let cards = MockFeedBuilder().makeSessionNow(number: 1).cards
        #expect(cards.contains { $0.feature == .similarShots })
        #expect(cards.contains { $0.feature == .duplicates })
        #expect(cards.contains { $0.feature == .screenshotBatches })
        #expect(cards.filter { $0.items.count == 1 }.allSatisfy { $0.feature == nil })
    }

    @Test(arguments: [TierFeature.similarShots, .duplicates, .screenshotBatches])
    func aBundleWithoutItsFeatureSplitsIntoSingles(_ feature: TierFeature) throws {
        let card = try #require(MockFeedBuilder().makeSessionNow(number: 1).cards.first { $0.feature == feature })
        let split = card.unbundled(unless: Set(TierFeature.allCases).subtracting([feature]))

        #expect(split.map(\.items) == card.items.map { [$0] }, "Same items, same order")
        #expect(split.allSatisfy { $0.feature == nil })
        #expect(card.unbundled(unless: [feature]) == [card])
    }

    // MARK: Video editing (JUN-7, JUN-50)

    /// Trimming and compression are separate toggles. With the trimmer off and compression on, the
    /// viewer offers compression over a plain seek bar (`EditDraft` with `canTrim` false).
    @Test func theVideoTogglesAreSeparate() async {
        let features = tunables(defaults: freshDefaults())
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(),
                               defaults: freshDefaults(), features: features)
        #expect(vm.videoEditOptions.canTrim && vm.videoEditOptions.canCompress)

        features.set(.videoTrimmer, .off)
        #expect(!vm.videoEditOptions.canTrim)
        #expect(vm.videoEditOptions.canCompress)

        features.set(.videoTrimmer, .universal)
        features.set(.videoCompression, .off)
        #expect(vm.videoEditOptions.canTrim)
        #expect(!vm.videoEditOptions.canCompress)
    }

    @Test func compressionCanBeLimitedToATier() async {
        let features = tunables(defaults: freshDefaults())
        features.set(.videoCompression, .paidOnly)
        let free = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false),
                                 defaults: freshDefaults(), features: features)
        let paid = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: true),
                                 defaults: freshDefaults(), features: features)
        #expect(!free.videoEditOptions.canCompress)
        #expect(paid.videoEditOptions.canCompress)
    }

    @Test func singlesNeverChange() throws {
        let card = try #require(MockFeedBuilder().makeSessionNow(number: 1).cards.first { $0.feature == nil })
        #expect(card.unbundled(unless: []) == [card])
    }

    // MARK: Feed

    @Test func aFreeUserGetsPaidOnlyBundlesAsSinglesUntilUnlocked() async {
        let entitlements = TestEntitlements(isUnlocked: false)
        let features = FeatureAvailabilityTunables.fixed([.similarShots: .paidOnly, .duplicates: .universal, .screenshotBatches: .universal])
        let vm = FeedViewModel(
            library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: entitlements,
            defaults: freshDefaults(), features: features
        )
        await vm.start()
        let free = vm.session?.cards ?? []
        #expect(!free.isEmpty)
        #expect(!free.contains { $0.feature == .similarShots })
        #expect(free.contains { $0.feature == .duplicates })

        entitlements.isUnlocked = true
        await vm.admin.adminRebuildDeck()
        #expect(vm.session?.cards.contains { $0.feature == .similarShots } == true)
    }
}
