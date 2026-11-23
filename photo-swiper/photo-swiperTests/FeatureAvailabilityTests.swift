import Foundation
import Testing
@testable import photo_swiper

/// Developer mode's feature access: what each plan gets of every feature (off, locked or unlocked),
/// that saved overrides from before JUN-87 carry over, and that a bundle that's off for a user turns
/// into single cards instead of going missing, while a locked one stays a bundle.
@MainActor
struct FeatureAvailabilityTests {
    private func tunables(defaults: UserDefaults, devMode: DistributionEnvironment = .debug) -> FeatureAvailabilityTunables {
        FeatureAvailabilityTunables(defaults: defaults, devMode: DevMode(environment: devMode, defaults: defaults))
    }

    // MARK: Access

    @Test func eachPlanReadsItsOwnAccess() {
        let access = PlanAccess(free: .locked, paid: .off)
        #expect(access.access(isUnlocked: false) == .locked)
        #expect(access.access(isUnlocked: true) == .off)
        #expect(FeatureAccess.locked.isVisible)
        #expect(FeatureAccess.unlocked.isVisible)
        #expect(!FeatureAccess.off.isVisible)
    }

    @Test func theFilterPillAndTopCategoriesAreLockedForFreeAndTheRestWorkForEveryone() {
        let features = tunables(defaults: freshDefaults())
        for feature in [TierFeature.feedFilters, .topCategories] {
            #expect(features.planAccess(feature) == PlanAccess(free: .locked, paid: .unlocked))
        }
        for feature in [TierFeature.similarShots, .duplicates, .screenshotBatches, .videoTrimmer, .videoCompression, .sharing] {
            #expect(features.planAccess(feature) == .everyone)
        }
        #expect(features.visible(isUnlocked: false) == Set(TierFeature.allCases), "Locked still shows")
        #expect(features.visible(isUnlocked: true) == Set(TierFeature.allCases))
        #expect(!features.isCustomized)
    }

    // MARK: Tunables

    @Test func anOverrideIsSavedPerPlanAndApplies() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.similarShots, on: .free, .off)
        features.set(.duplicates, on: .paid, .locked)

        #expect(features.access(.similarShots, isUnlocked: false) == .off)
        #expect(features.access(.similarShots, isUnlocked: true) == .unlocked, "The other plan is untouched")
        #expect(features.access(.duplicates, isUnlocked: true) == .locked)
        #expect(!features.visible(isUnlocked: false).contains(.similarShots))
        #expect(features.isCustomized)
        #expect(tunables(defaults: defaults).planAccess(.similarShots) == PlanAccess(free: .off, paid: .unlocked),
                "Remembered across launches")
    }

    @Test func settingTheDefaultClearsTheOverride() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.screenshotBatches, on: .free, .locked)
        features.set(.screenshotBatches, on: .free, .unlocked)

        #expect(!features.isCustomized)
        #expect(defaults.string(forKey: TierFeature.screenshotBatches.defaultsKey(.free)) == nil)
    }

    @Test func overridesAreIgnoredWithDeveloperModeOff() {
        let defaults = freshDefaults()
        tunables(defaults: defaults).set(.similarShots, on: .free, .off)

        let features = tunables(defaults: defaults, devMode: .production)
        #expect(features.planAccess(.similarShots) == .everyone)
        #expect(features.visible(isUnlocked: false) == Set(TierFeature.allCases))
    }

    @Test func resetForgetsEveryOverride() {
        let defaults = freshDefaults()
        let features = tunables(defaults: defaults)
        features.set(.similarShots, on: .free, .off)
        features.set(.feedFilters, on: .paid, .locked)
        features.resetToDefaults()

        #expect(!features.isCustomized)
        #expect(!tunables(defaults: defaults).isCustomized)
    }

    // MARK: Migration (JUN-87)

    @Test(arguments: [
        ("universal", PlanAccess(free: .unlocked, paid: .unlocked)),
        ("freeOnly", PlanAccess(free: .unlocked, paid: .off)),
        ("paidOnly", PlanAccess(free: .off, paid: .unlocked)),
        ("off", PlanAccess(free: .off, paid: .off)),
    ])
    func anOldOverrideMovesToBothPlans(_ old: String, _ expected: PlanAccess) {
        let defaults = freshDefaults()
        defaults.set(old, forKey: TierFeature.duplicates.legacyDefaultsKey)

        #expect(tunables(defaults: defaults).planAccess(.duplicates) == expected)
        #expect(defaults.string(forKey: TierFeature.duplicates.legacyDefaultsKey) == nil, "The old key is gone")
        #expect(tunables(defaults: defaults).planAccess(.duplicates) == expected, "And it's still there next launch")
        for plan in Plan.allCases where expected[plan] == .unlocked {
            #expect(defaults.string(forKey: TierFeature.duplicates.defaultsKey(plan)) == nil, "A plan left at its default isn't saved")
        }
    }

    @Test func anOldUniversalOverrideIsntACustomization() {
        let defaults = freshDefaults()
        defaults.set("universal", forKey: TierFeature.duplicates.legacyDefaultsKey)
        #expect(!tunables(defaults: defaults).isCustomized)
    }

    /// Migration rewrites the keys whatever the Developer mode setting; they only apply once it's on.
    @Test func anOldOverrideMigratesWithDeveloperModeOffAndAppliesOnceItsOn() {
        let defaults = freshDefaults()
        defaults.set("paidOnly", forKey: TierFeature.duplicates.legacyDefaultsKey)

        #expect(tunables(defaults: defaults, devMode: .production).planAccess(.duplicates) == .everyone)
        #expect(defaults.string(forKey: TierFeature.duplicates.legacyDefaultsKey) == nil)
        #expect(tunables(defaults: defaults).planAccess(.duplicates) == PlanAccess(free: .off, paid: .unlocked))
    }

    @Test func anOldOverrideOnANewlyLockedFeatureKeepsItsMeaning() {
        let defaults = freshDefaults()
        // Not possible before JUN-87, but the mapping must not fall back to today's locked default.
        defaults.set("universal", forKey: TierFeature.feedFilters.legacyDefaultsKey)
        #expect(tunables(defaults: defaults).planAccess(.feedFilters) == .everyone)
    }

    @Test func anUnknownOldValueIsDropped() {
        let defaults = freshDefaults()
        defaults.set("everyone", forKey: TierFeature.similarShots.legacyDefaultsKey)

        let features = tunables(defaults: defaults)
        #expect(features.planAccess(.similarShots) == .everyone)
        #expect(!features.isCustomized)
        #expect(defaults.string(forKey: TierFeature.similarShots.legacyDefaultsKey) == nil)
    }

    @Test func aNewOverrideWinsOverAnOldOne() {
        let defaults = freshDefaults()
        defaults.set("off", forKey: TierFeature.similarShots.legacyDefaultsKey)
        defaults.set("locked", forKey: TierFeature.similarShots.defaultsKey(.free))

        #expect(tunables(defaults: defaults).planAccess(.similarShots) == PlanAccess(free: .locked, paid: .off))
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
    func aBundleWhoseFeatureIsOffSplitsIntoSingles(_ feature: TierFeature) throws {
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

        for plan in Plan.allCases { features.set(.videoTrimmer, on: plan, .off) }
        #expect(!vm.videoEditOptions.canTrim)
        #expect(vm.videoEditOptions.canCompress)

        for plan in Plan.allCases {
            features.set(.videoTrimmer, on: plan, .unlocked)
            features.set(.videoCompression, on: plan, .off)
        }
        #expect(vm.videoEditOptions.canTrim)
        #expect(!vm.videoEditOptions.canCompress)
    }

    @Test func compressionCanBeOffForOnePlan() async {
        let features = tunables(defaults: freshDefaults())
        features.set(.videoCompression, on: .free, .off)
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

    @Test func aLockedVideoEditStillShows() async {
        let locked = PlanAccess(free: .locked, paid: .unlocked)
        let features = FeatureAvailabilityTunables.fixed([.videoTrimmer: locked, .videoCompression: locked])
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false),
                               defaults: freshDefaults(), features: features)
        #expect(vm.videoEditOptions.canTrim && vm.videoEditOptions.canCompress)
    }

    @Test func aFreeUserGetsBundlesThatAreOffForThemAsSinglesUntilUnlocked() async {
        let entitlements = TestEntitlements(isUnlocked: false)
        let features = FeatureAvailabilityTunables.fixed([.similarShots: PlanAccess(free: .off, paid: .unlocked)])
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

    @Test func aLockedBundleIsDealtWhole() async {
        let features = FeatureAvailabilityTunables.fixed([.similarShots: PlanAccess(free: .locked, paid: .unlocked)])
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false),
                               defaults: freshDefaults(), features: features)
        await vm.start()
        #expect(vm.session?.cards.contains { $0.feature == .similarShots } == true)
    }
}
