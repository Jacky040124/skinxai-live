import Foundation
import UserNotifications
import EczemaKit

/// Real mode only: one local heads-up per day when scratching is above 1.5× your usual for the
/// second day in a row (the anomaly rule of the analysis). Silent without notification permission.
@MainActor
final class FlareAlerts: NSObject, UNUserNotificationCenterDelegate {
    private static let lastKey = "et.lastFlareAlert"
    /// Opens the Insight tab when the notification is tapped.
    var onOpen: (() -> Void)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func check(_ d: TwinDataset, calendar: Calendar = .current) {
        guard !d.isDemo, d.days.count >= 2, d.baselineMinutesPerDay > 0 else { return }
        let limit = 1.5 * d.baselineMinutesPerDay
        let today = d.days[d.days.count - 1]
        let yesterday = d.days[d.days.count - 2]
        guard today.scratchMinutes > limit, yesterday.scratchMinutes > limit else { return }
        let key = today.day.formatted(.iso8601.year().month().day())
        guard UserDefaults.standard.string(forKey: Self.lastKey) != key else { return }
        UserDefaults.standard.set(key, forKey: Self.lastKey)

        let content = UNMutableNotificationContent()
        content.title = "Scratching is up two days in a row"
        content.body = "\(Int(today.scratchMinutes.rounded())) min so far today, about \(Int(d.baselineMinutesPerDay.rounded())) on a usual day. Claude can look at what changed."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "flare-\(key)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let isFlare = response.notification.request.identifier.hasPrefix("flare-")
        Task { @MainActor in
            if isFlare { self.onOpen?() }
            completionHandler()
        }
    }
}
