import SwiftUI
import EczemaKit

/// Scripted interactions for visual QA and recordings (`scripts/video shell ios today 12 -shellDemo tag`).
/// Does nothing unless the `-shellDemo <name>` launch argument is present. Each script drives the
/// same code paths a person would (buttons post the same commands, the watch path is WatchLink's).
///   tag         open the quick-tag sheet, pick three chips, save (toast)
///   onboarding  show onboarding, page through it, finish (frame folds into the top bar)
///   report      open "Share with my doctor"
///   settings    open Settings, time travel to test day 6 and back
///   watch       a live scratch episode arrives from the watch (merge + toast)
///   scan        open the tag sheet, open the label scanner, read the sample label, use it
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
