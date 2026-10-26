import UIKit
import UserNotifications

/// Receives taps on refill reminders, including the one that launches the app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Already in the app: the countdown says it all, so no banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard RefillReminder.allIDs.contains(response.notification.request.identifier) else { return }
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
