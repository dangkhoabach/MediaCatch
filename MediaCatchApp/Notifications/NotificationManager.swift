import AppKit
import UserNotifications

/// Native `UNUserNotificationCenter` notifications with click-through
/// support — replaces `notification.rs`'s `notify-rust` + dedicated-OS-thread
/// workaround (that existed only to get a click callback out of the legacy
/// NSUserNotificationCenter backend, and needed a fake bundle-id fallback for
/// unsigned dev builds; `UNUserNotificationCenter`'s delegate gives a click
/// callback natively with none of that). Copied from SignalBar's
/// already-proven code,
/// simplified: this app's notifications only ever need a plain click (no
/// dedicated action button/category — `notification.rs`'s "View" action
/// button existed solely to satisfy the legacy backend's click-detection
/// quirk, not a distinct feature).
///
/// `@MainActor`-isolated because everything it touches after a click
/// (`NSApp`, windows, `onRouteSelected`) must run on the main thread; the two
/// `UNUserNotificationCenterDelegate` methods are `nonisolated` because the
/// system calls them on an arbitrary thread, and immediately hop back via
/// `Task { @MainActor in ... }` after extracting only the `Sendable`
/// primitive (the route string) first.
@MainActor
public final class NotificationManager: NSObject, @unchecked Sendable {
    public static let shared = NotificationManager()

    /// Set once a real router exists. Until then, a click-through
    /// still brings the app forward — it just has nowhere in-app to
    /// navigate to yet.
    public var onRouteSelected: ((String) -> Void)?

    // `nonisolated`: read from the nonisolated delegate method below, which
    // the system calls off the main actor.
    nonisolated private static let routeUserInfoKey = "route"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// The real, current permission state — unlike
    /// `tauri-plugin-notification`'s desktop backend, which always reports
    /// "Granted" regardless of what the user actually chose.
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Only call this at the moment the user actually opts in (flipping the
    /// Settings toggle), never at app launch, so the permission
    /// prompt has context instead of appearing out of nowhere.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Generic entry point — mirrors `notification.rs::show`'s
    /// title/body/route shape. Does not check the user's "Notifications"
    /// setting itself; the caller owns that toggle, same division of
    /// responsibility as the Rust version (`show_notification` command vs.
    /// the frontend's `getNotificationsEnabled()`).
    public func notify(title: String, body: String, route: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let route {
            content.userInfo = [Self.routeUserInfoKey: route]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Deep-links to System Settings' Notifications pane, for a "Manage in
    /// System Settings" affordance next to the in-app toggle.
    public static func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Shows the banner even while the app is frontmost — otherwise
    /// foreground-delivered notifications are silently suppressed by default.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = response.notification.request.content.userInfo[NotificationManager.routeUserInfoKey] as? String
        Task { @MainActor in
            WindowPresenter.showMainWindow()
            if let route {
                NotificationManager.shared.onRouteSelected?(route)
            }
        }
        completionHandler()
    }
}
