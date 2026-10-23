import SwiftUI
import EczemaKit

/// Owns the app-frame services and wires them to `AppState` once, when the root view appears.
@MainActor
final class ShellServices: ObservableObject {
    let toasts = ToastCenter()
    let tour = DemoTour()
    let data = DataModeController()
    let access = DeviceAccess()
    let watch = WatchLink()
    let alerts = FlareAlerts()
    private var attached = false

    func attach(_ app: AppState) {
        guard !attached else { return }
        attached = true
        watch.activate()
        alerts.install()
        alerts.onOpen = { [weak app] in app?.select(.insight) }
        data.alerts = alerts
        data.attach(app, toasts: toasts, watch: watch, access: access)
        Task { await access.refresh() }
        Self.firstLaunch(app)
        if UserDefaults.standard.string(forKey: "autoplay") == "tour" {
            tour.start(app: app, delay: 0.3)
        }
        ShellDemoScript.runIfRequested(app: app, services: self)
    }

    /// Contract: onboarding auto-shows only on the very first launch AND only without `-screen`.
    private static func firstLaunch(_ app: AppState) {
        let defaults = UserDefaults.standard
        let launchedBefore = defaults.bool(forKey: Keys.launchedBefore)
        defaults.set(true, forKey: Keys.launchedBefore)
        let args = ProcessInfo.processInfo.arguments
        if !launchedBefore && !args.contains("-screen") && defaults.string(forKey: "autoplay") == nil {
            app.showOnboarding = true
        }
    }

    enum Keys {
        static let launchedBefore = "et.launchedBefore"
        static let didOnboard = "et.didOnboard"
    }
}
