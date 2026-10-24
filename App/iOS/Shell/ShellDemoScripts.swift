import SwiftUI
import EczemaKit

/// Scripted interactions for visual QA and recordings (`scripts/video shell ios today 12 -shellDemo tag`).
/// Does nothing unless the `-shellDemo <name>` launch argument is present. Each script drives the
/// same code paths a person would (buttons post the same commands, the watch path is WatchInbox's).
///   tag         open the quick-tag sheet, pick three chips, save (toast)
///   onboarding  show onboarding, page through it, finish (frame folds into the top bar)
///   report      open "Share with my doctor"
///   settings    open Settings, time travel to test day 6 and back
///   sheetToast  open Settings and raise a toast (it must show above the sheet)
///   keychain    save / update / read / delete a throwaway value with the Settings Keychain item
///               (skipped when a real key is stored)
///   watch       a live scratch episode arrives from the watch (merge + toast)
///   scan        open the tag sheet, open the label scanner, read the sample label, use it
///   tabs        Today → Insight → Test → Trends → Today, 2 s apart (page transitions)
///   midnight    the app "stayed open overnight": yesterday's story + a live episode from today,
///               then midnight passes (counts dataset updates: the overlay must not loop)
///   hour        today's story as it looked 4 hours ago, then the top of the hour passes
///   inbox       a watch payload arrives before anyone listens (background wake), then the frame attaches
///   haptics     card → tab, tab bar → tab and "Start test" paths: one haptic per touch
@MainActor
enum ShellDemoScript {
    static func runIfRequested(app: AppState, services: ShellServices) {
        guard let name = UserDefaults.standard.string(forKey: "shellDemo") else { return }
        Task { try? await run(name, app: app, services: services) }
    }

    private static func pause(_ s: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    private static func post(_ command: String) {
        NotificationCenter.default.post(name: .shellDemo, object: command)
    }

    private static func run(_ name: String, app: AppState, services: ShellServices) async throws {
        switch name {
        case "tag":
            try await pause(1.4)
            withAnimation(TagSheetHost.openAnimation(false)) { app.showTagSheet = true }
            try await pause(1.4)
            for kind in ["pet", "dairy", "wool"] {
                post("tag.toggle:\(kind)")
                try await pause(0.55)
            }
            try await pause(0.8)
            post("tag.save")
        case "onboarding":
            app.showOnboarding = true
            try await pause(5.5)
            post("onboarding.next")
            try await pause(3.5)
            post("onboarding.next")
            try await pause(3.0)
            post("onboarding.next")
        case "report":
            try await pause(0.8)
            app.showReport = true
        case "settings":
            try await pause(0.8)
            app.showSettings = true
            try await pause(2.6)
            services.data.travel(to: .test(6))
            try await pause(2.4)
            services.data.travel(to: .flare(StoryPoint.flareLength))
        case "sheetToast":
            try await pause(0.8)
            app.showSettings = true
            try await pause(1.6)
            services.toasts.show("Toasts show above sheets", mood: .info)
        case "keychain":
            try await pause(1.0)
            guard SettingsKeychain.read() == nil else {
                services.toasts.show("A key is stored · check skipped", mood: .info)
                return
            }
            let saved = SettingsKeychain.save("qa-placeholder-one") && SettingsKeychain.read() == "qa-placeholder-one"
            let updated = SettingsKeychain.save("qa-placeholder-two") && SettingsKeychain.read() == "qa-placeholder-two"
            let deleted = SettingsKeychain.delete() && SettingsKeychain.read() == nil && !SettingsKeychain.hasKey
            let ok = saved && updated && deleted
            services.toasts.show(ok ? "Keychain check passed" : "Keychain unavailable (OSStatus \(SettingsKeychain.probe()))",
                                 mood: ok ? .done : .warning, seconds: 6)
        case "scan":
            try await pause(1.0)
            withAnimation(TagSheetHost.openAnimation(false)) { app.showTagSheet = true }
            try await pause(1.2)
            post("tag.scan")
            try await pause(2.2)
            post("scan.sample")
            try await pause(2.8)
            post("scan.use")
        case "watch":
            try await pause(3.0)
            let end = Date()
            let episode = ScratchEpisode(start: end.addingTimeInterval(-95), end: end, meanHz: 4.2, meanRMS: 0.41,
                                         intense: true, source: .live, label: .confirmed)
            services.watch.onEpisodes?([episode])
        case "tabs":
            for tab in [Tab.insight, .experiment, .trends, .today] {
                try await pause(2.0)
                app.select(tab)
            }
        case "midnight":
            try await pause(2.0)
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
            app.update { $0 = DemoData.make(today: yesterday, revealThroughHour: 23) }
            var updates = 0
            let counter = app.$dataset.dropFirst().sink { _ in updates += 1 }
            let end = Date()
            services.watch.onEpisodes?([ScratchEpisode(start: end.addingTimeInterval(-80), end: end, meanHz: 4.0,
                                                       meanRMS: 0.3, intense: false, source: .live, label: .confirmed)])
            try await pause(2.0)
            let stale = updates
            NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
            try await pause(1.5)
            counter.cancel()
            let onToday = app.dataset.today.map { Calendar.current.isDateInToday($0.day) } ?? false
            let live = app.dataset.episodes.contains { $0.source == .live }
            let ok = stale == 0 && onToday && live
            services.toasts.show("\(stale) updates while stale · \(onToday ? "on today" : "still yesterday") · live \(live ? "merged" : "missing")",
                                 mood: ok ? .done : .warning, seconds: 8)
        case "inbox":
            try await pause(1.5)
            // As when WatchConnectivity wakes the app in the background: nobody listens yet.
            let listener = services.watch.onEpisodes
            services.watch.onEpisodes = nil
            let end = Date()
            let episode = ScratchEpisode(start: end.addingTimeInterval(-70), end: end, meanHz: 4.4, meanRMS: 0.38,
                                         intense: true, source: .live, label: .confirmed)
            let data = try JSONEncoder().encode([episode])
            services.watch.simulateDelivery(["kind": "episodes", "data": data])
            try await pause(1.0)
            let savedFirst = RealStore.loadEpisodes().contains { $0.id == episode.id }
            services.watch.onEpisodes = listener      // the app frame attaches
            try await pause(2.4)
            let merged = app.dataset.episodes.contains { $0.id == episode.id }
            services.toasts.show("Before anyone listened: \(savedFirst ? "saved" : "lost") · then \(merged ? "merged" : "never merged")",
                                 mood: savedFirst && merged ? .done : .warning, seconds: 8)
        case "hour":
            try await pause(2.5)
            services.data.rewindStoryClock(hours: 4)
            try await pause(3.0)
            services.data.keepStoryOnToday()
        case "haptics":
            try await pause(1.5)
            Haptics.tap()                         // a card's press tap…
            let press = Haptics.lastTapAt
            app.select(.insight)                  // …and its action
            let card = Haptics.lastTapAt == press
            try await pause(1.2)
            let before = Haptics.lastTapAt
            app.select(.trends)                   // a switch with no press tap before it (tour, alert)
            let tab = Haptics.lastTapAt != before
            try await pause(1.2)
            Haptics.tap()                         // "Start a 10-day test" press tap…
            let start = Haptics.lastTapAt
            app.startExperiment()                 // …then only the success haptic
            let started = Haptics.lastTapAt == start
            services.toasts.show("Card → tab \(card ? "1 tap" : "2 taps") · plain switch \(tab ? "taps" : "silent") · start \(started ? "success only" : "extra tap")",
                                 mood: card && tab && started ? .done : .warning, seconds: 8)
        default:
            break
        }
    }
}

extension Notification.Name {
    /// QA commands from `ShellDemoScript` ("tag.toggle:<kind>", "tag.save", "tag.scan", "scan.sample",
    /// "scan.use", "onboarding.next").
    static let shellDemo = Notification.Name("et.shellDemo")
}
