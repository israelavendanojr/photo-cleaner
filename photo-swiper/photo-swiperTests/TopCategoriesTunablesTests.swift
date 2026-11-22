import Foundation
import Testing
@testable import photo_swiper

/// Developer mode's Top Categories limits (JUN-88), and which rows open the feed while the section is locked.
@MainActor
struct TopCategoriesTunablesTests {
    private func tunables(defaults: UserDefaults, devMode: DistributionEnvironment = .debug) -> TopCategoriesTunables {
        TopCategoriesTunables(defaults: defaults, devMode: DevMode(environment: devMode, defaults: defaults))
    }

    @Test func threeRowsWithTheFirstFreeByDefault() {
        let limits = tunables(defaults: freshDefaults()).limits
        #expect(limits == TopCategoriesLimits(count: 3, freeRows: 1))
    }

    @Test func anOverrideIsClampedSavedAndApplies() {
        let defaults = freshDefaults()
        let topCategories = tunables(defaults: defaults)
        topCategories.set(.count, 50)
        topCategories.set(.freeRows, 2)

        #expect(topCategories.limits == TopCategoriesLimits(count: 8, freeRows: 2), "Clamped to 1...8")
        #expect(topCategories.isCustomized)
        #expect(tunables(defaults: defaults).limits.count == 8, "Remembered across launches")
    }

    @Test func settingTheDefaultClearsTheOverride() {
        let defaults = freshDefaults()
        let topCategories = tunables(defaults: defaults)
        topCategories.set(.count, 5)
        topCategories.set(.count, 3)
        #expect(!topCategories.isCustomized)
        #expect(defaults.object(forKey: TopCategoriesTunable.count.defaultsKey) == nil)
    }

    @Test func overridesAreIgnoredWithDeveloperModeOff() {
        let defaults = freshDefaults()
        tunables(defaults: defaults).set(.freeRows, 0)
        #expect(tunables(defaults: defaults, devMode: .production).limits == .standard)
    }

    @Test func resetForgetsEveryOverride() {
        let defaults = freshDefaults()
        let topCategories = tunables(defaults: defaults)
        topCategories.set(.count, 6)
        topCategories.set(.freeRows, 0)
        topCategories.resetToDefaults()
        #expect(!topCategories.isCustomized)
        #expect(!tunables(defaults: defaults).isCustomized)
    }

    @Test func unlockedEveryRowOpensTheFeedAndLockedOnlyTheFreeOnes() {
        let limits = TopCategoriesLimits(count: 3, freeRows: 1)
        #expect((0..<3).allSatisfy { limits.opensFeed(rowAt: $0, access: .unlocked) })
        #expect(limits.opensFeed(rowAt: 0, access: .locked))
        #expect(!limits.opensFeed(rowAt: 1, access: .locked))
        #expect(!limits.opensFeed(rowAt: 2, access: .locked))
        #expect(!TopCategoriesLimits(count: 3, freeRows: 0).opensFeed(rowAt: 0, access: .locked), "No free rows: every row asks")
        #expect(!limits.opensFeed(rowAt: 0, access: .off))
    }

    @Test func aFreeUserGetsLockedTopCategoriesAndTheirPaywall() async {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: false),
                               defaults: freshDefaults(), topCategories: .fixed())
        #expect(vm.featureAccess(.topCategories) == .locked, "Locked for free by default")
        vm.requestUnlock(.topCategories)
        #expect(vm.lockedPrompt == LockedPrompt(feature: .topCategories, cardID: nil))
        vm.lockedPromptDismissed()
        #expect(vm.lockedPrompt == nil)
    }

    @Test func anUnlockedUserNeverGetsTheTopCategoriesPaywall() async {
        let vm = FeedViewModel(library: FakeLibrary(), builder: MockFeedBuilder(), entitlements: TestEntitlements(isUnlocked: true),
                               defaults: freshDefaults(), topCategories: .fixed())
        #expect(vm.featureAccess(.topCategories) == .unlocked)
        vm.requestUnlock(.topCategories)
        #expect(vm.lockedPrompt == nil)
    }
}
