import Foundation

/// When to ask for an App Store review: right after a delete that freed a lot, never on the
/// first-ever delete, and at most once per app version. `FeedViewModel` also skips it after a
/// purchase and while the wall is up; RootView asks once the freed confirmation has closed.
enum ReviewPrompt {
    /// 100 MB, in the decimal units `Format.size` shows.
    static let minimumFreedBytes: Int64 = 100_000_000

    /// - Parameter priorDeletes: Deletes that went through before this one.
    static func isEligible(freedBytes: Int64, priorDeletes: Int, lastAskedVersion: String?, currentVersion: String) -> Bool {
        freedBytes >= minimumFreedBytes && priorDeletes > 0 && lastAskedVersion != currentVersion
    }
}
