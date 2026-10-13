import Foundation
import UserNotifications
import FinanceFeatures

/// Receives notification taps and hands them to the `AppRouter`.
///
/// Installed in `PersonalFinanceApp.init`, before launch finishes, so a tap that
/// launches the app is not lost. The route is stored as pending on the router
/// and resolved by `RootView` once the UI is on screen.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Set whenever a store opens (and again after a retry).
    @MainActor var router: AppRouter?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show reminders and budget alerts even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let route = NotificationRoute(userInfo: response.notification.request.content.userInfo)
        else { return }
        await MainActor.run { router?.receive(route) }
    }
}
