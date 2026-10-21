import Foundation

/// App-wide names. The app name isn't final, so copy reads it from here.
enum AppInfo {
    static let name = "Photo Swiper"
}

/// `UserDefaults` keys shared by view models and `@AppStorage`.
enum DefaultsKey {
    /// Set once the user taps Allow on the photo access screen.
    static let hasOnboarded = "hasOnboarded"
    /// Set after the first swipe, so the swipe hint shows once ever.
    static let hasSeenSwipeHint = "hasSeenSwipeHint"
}
