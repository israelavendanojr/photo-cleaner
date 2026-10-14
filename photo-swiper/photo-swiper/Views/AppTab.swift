import Foundation

/// The app's top-level tabs.
enum AppTab: CaseIterable {
    case feed, library

    var tabItem: PillTabBar<AppTab>.Item {
        switch self {
        case .feed:
            .init(tab: self, title: "Feed", systemImage: "square.stack", selectedSystemImage: "square.stack.fill")
        case .library:
            .init(tab: self, title: "Library", systemImage: "photo.on.rectangle", selectedSystemImage: "photo.fill.on.rectangle.fill")
        }
    }
}
