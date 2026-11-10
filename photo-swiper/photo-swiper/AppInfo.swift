import Foundation

/// App-wide names and launch links.
///
/// Settings hides a row whose value is nil (debug builds show it greyed out, "Not set yet"),
/// and the wall's legal links follow the same values.
enum AppInfo {
    /// The display name, CFBundleDisplayName. Set it as `APP_DISPLAY_NAME` in AppName.xcconfig, not here.
    /// All in-app copy that names the app reads this.
    static let name: String = {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        // Only for contexts without the app's Info.plist. `AppInfoTests` checks the real one is set.
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "Bristle"
    }()

    // MARK: Launch links

    /// Apple's standard EULA. Final.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicyURL: URL? = URL(string: "https://getbristle.app/privacy")
    static let supportURL: URL? = URL(string: "https://getbristle.app/support")
    static let supportEmail: String? = "support@getbristle.app"
    /// The numeric App Store ID, e.g. "1234567890". Enables "Rate".
    static let appStoreID: String? = nil // TODO(launch)

    /// Opens the App Store's write-a-review page.
    static var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    /// The launch values still unset. `testLaunchURLsAreSet` fails on these in Release.
    static var missingLaunchValues: [String] {
        [
            privacyPolicyURL == nil ? "privacyPolicyURL" : nil,
            supportURL == nil ? "supportURL" : nil,
            supportEmail == nil ? "supportEmail" : nil,
        ].compactMap { $0 }
    }

    // MARK: Version

    /// CFBundleShortVersionString, e.g. "1.0".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// CFBundleVersion, e.g. "12".
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

/// `UserDefaults` keys shared by view models and `@AppStorage`.
enum DefaultsKey {
    /// Set once the user taps Allow on the photo access screen.
    static let hasOnboarded = "hasOnboarded"
    /// Set after the first swipe, so the swipe hint shows once ever.
    static let hasSeenSwipeHint = "hasSeenSwipeHint"
    /// The last unlock state StoreKit reported, so launch doesn't flash locked. StoreKit corrects it.
    static let storeKitUnlocked = "storeKitUnlocked"
    /// Set once items wrongly settled as gone under limited access have been looked for with full access.
    static let reopenedLimitedAccessGone = "reopenedLimitedAccessGone"
    /// Debug builds only: the stand-in unlock was bought. Release builds never read it.
    static let debugUnlocked = "debugUnlocked"
    /// Debug builds only: show onboarding on the next launch even though photo access was already answered.
    static let debugShowOnboarding = "debugShowOnboarding"
    /// The free swipe allowance (`SwipeAllowance`), as JSON.
    static let swipeAllowance = "swipeAllowance"
    /// The user asked to be told when swipes are back. Settings can turn it off.
    static let refillRemindersOptIn = "refillRemindersOptIn"
    /// Fire dates of recently scheduled refill reminders, for the two-a-day cap.
    static let refillReminderLog = "refillReminderLog"
    /// The app version the review prompt last asked on, so it asks at most once per version.
    static let reviewPromptVersion = "reviewPromptVersion"
    /// How many deletes from the pile have gone through. The first never asks for a review.
    static let deleteCount = "deleteCount"
    /// When the unlock offer after a delete last showed, for its once-a-day limit.
    static let deleteUpsellShownAt = "deleteUpsellShownAt"
    /// The confetti for a fully reviewed library has played. Cleared when progress drops below 100%.
    static let celebratedComplete = "celebratedComplete"
}
