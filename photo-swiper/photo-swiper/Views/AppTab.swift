import Foundation

/// The app's top-level tabs. Admin shows only while Developer mode is on (see `DevMode`).
enum AppTab: CaseIterable {
    case feed, library, admin

    var tabItem: PillTabBar<AppTab>.Item {
        switch self {
        case .feed: .init(tab: self, title: "Feed")
        case .library: .init(tab: self, title: "Library")
        case .admin: .init(tab: self, title: "Admin")
        }
    }

    /// The tabs the bar shows. Admin Tools belong to Developer mode, so their tab goes when it's off.
    static func visible(devModeEnabled: Bool) -> [AppTab] {
        devModeEnabled ? allCases : allCases.filter { $0 != .admin }
    }

    /// Where `tab` lands once Developer mode is `devModeEnabled`: the feed if `tab` is no longer shown,
    /// so the screen never stays on a tab the bar has dropped.
    static func fallback(_ tab: AppTab, devModeEnabled: Bool) -> AppTab {
        visible(devModeEnabled: devModeEnabled).contains(tab) ? tab : .feed
    }
}
