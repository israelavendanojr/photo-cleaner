import Testing
@testable import photo_swiper

/// The Admin tab follows Developer mode: shown only while it's on, and never left showing once it's off.
@MainActor
struct AppTabTests {
    @Test func adminShowsOnlyInDeveloperMode() {
        #expect(AppTab.visible(devModeEnabled: true) == [.feed, .library, .admin])
        #expect(AppTab.visible(devModeEnabled: false) == [.feed, .library])
    }

    @Test func turningDeveloperModeOffOnTheAdminTabGoesToTheFeed() {
        #expect(AppTab.fallback(.admin, devModeEnabled: false) == .feed)
    }

    @Test(arguments: [AppTab.feed, .library])
    func otherTabsStayPut(_ tab: AppTab) {
        #expect(AppTab.fallback(tab, devModeEnabled: false) == tab)
        #expect(AppTab.fallback(tab, devModeEnabled: true) == tab)
    }

    @Test func theAdminTabStaysWhileDeveloperModeIsOn() {
        #expect(AppTab.fallback(.admin, devModeEnabled: true) == .admin)
    }

    /// Developer mode exists in production for no one, so neither does the tab.
    @Test func appStoreBuildsNeverShowTheAdminTab() {
        let devMode = DevMode(environment: .production, defaults: freshDefaults())
        devMode.setEnabled(true)
        #expect(!AppTab.visible(devModeEnabled: devMode.isEnabled).contains(.admin))
    }
}
