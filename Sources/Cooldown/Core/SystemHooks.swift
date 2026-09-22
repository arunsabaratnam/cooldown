import Foundation
import ServiceManagement
import UserNotifications

/// The notification centre and the login-item service both need a real app bundle.
/// Under `swift run` there is none, and `UNUserNotificationCenter.current()` traps, so
/// everything here checks first and quietly does nothing outside `Cooldown.app`.
private var isRunningAsApp: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
}

enum LoginItem {
    /// Returns what actually happened, which can differ from what was asked for when
    /// macOS refuses (an app outside /Applications, say).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isRunningAsApp else { return false }
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            return service.status == .enabled
        }
        return service.status == .enabled
    }
}

/// A notification at each 5-hour reset we know about, so you can get back to work the
/// moment the window is full again.
enum ResetNotifier {
    private static let prefix = "cooldown.reset."

    static func requestPermission() {
        guard isRunningAsApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces whatever was scheduled with one notification per upcoming reset.
    static func schedule(_ resets: [(ProviderID, Date)], enabled: Bool) {
        guard isRunningAsApp else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard enabled else { return }
            for (provider, date) in resets where date > Date() {
                let content = UNMutableNotificationContent()
                content.title = "\(provider.displayName) is back to full"
                content.body = "Its 5-hour window just reset."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, date.timeIntervalSinceNow),
                    repeats: false
                )
                center.add(UNNotificationRequest(
                    identifier: prefix + provider.rawValue,
                    content: content,
                    trigger: trigger
                ))
            }
        }
    }
}
