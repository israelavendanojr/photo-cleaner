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
    /// Debug builds only: the stand-in unlock was bought. Release builds never read it.
    static let debugUnlocked = "debugUnlocked"
    /// The free swipe allowance (`SwipeAllowance`), as JSON.
    static let swipeAllowance = "swipeAllowance"
    /// The user asked to be told when swipes are back. Settings can turn it off.
    static let refillRemindersOptIn = "refillRemindersOptIn"
    /// Fire dates of recently scheduled refill reminders, for the two-a-day cap.
    static let refillReminderLog = "refillReminderLog"
}
