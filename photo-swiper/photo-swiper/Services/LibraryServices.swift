import Foundation

/// Decides whether the app runs on the mock library or the real one.
enum LibraryServices {
    /// Previews always use mocks. Debug builds use them with `-mockLibrary YES` or `-startAt …`.
    /// Release builds never do: the mock services aren't compiled in.
    static var usesMock: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "mockLibrary") || defaults.string(forKey: "startAt") != nil
        #else
        return false
        #endif
    }
}
