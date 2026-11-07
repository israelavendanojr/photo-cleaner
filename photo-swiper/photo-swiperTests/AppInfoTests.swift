import Foundation
import Testing
@testable import photo_swiper

/// The display name has one source, `APP_DISPLAY_NAME`. These catch it drifting from what `AppInfo.name` shows.
struct AppInfoTests {
    private func plistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    @Test func nameIsTheBundleDisplayName() throws {
        let displayName = try #require(plistString("CFBundleDisplayName"))
        #expect(!AppInfo.name.isEmpty)
        #expect(AppInfo.name == displayName)
        #expect(!displayName.contains("$("))
    }

    @Test func photoUsageStringNamesTheApp() throws {
        let usage = try #require(plistString("NSPhotoLibraryUsageDescription"))
        #expect(usage.hasPrefix("\(AppInfo.name) "))
        #expect(!usage.contains("$("))
    }
}
