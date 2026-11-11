import UIKit
import UserNotifications

/// Receives taps on refill reminders, including the one that launches the app, and decides which
/// notifications show while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called off the main actor by the system; neither touches app state except through the main actor.

    /// Already in the app: the countdown says it all, so no banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions(for: notification.request.identifier)
    }

    /// Real reminders stay silent in the foreground. Admin Tools' test copies show a banner, since
    /// they're raised from inside the app to be seen.
    nonisolated static func foregroundOptions(for identifier: String) -> UNNotificationPresentationOptions {
        RefillReminder.isTest(identifier) ? [.banner, .list, .sound] : []
    }

    /// A tap on a refill reminder, or on Admin Tools' test copy of one, opens the feed.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard RefillReminder.routesToFeed(response.notification.request.identifier) else { return }
        await MainActor.run { NotificationRouter.shared.requestFeed() }
    }
}

/// Where a tapped notification sends the user. `RootView` watches it.
@Observable
@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()
    /// Bumped per tap on a refill reminder: show the feed.
    private(set) var feedRequests = 0

    func requestFeed() {
        feedRequests += 1
    }
}
