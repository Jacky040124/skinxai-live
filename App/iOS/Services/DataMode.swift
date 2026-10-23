import SwiftUI
import Combine
import EczemaKit

/// Where the app's data comes from (Settings → "Demo story"), demo time travel, and the live
/// inputs (watch episodes, Apple Health, weather).
///
/// - Demo (default): Douglas's story. Watch episodes detected live (`source == .live`) today are
///   added on top of the story, so scratching on stage makes the number tick up.
/// - Real: 14 days built from the watch, Apple Health and Open-Meteo (`RealDataBuilder`).
@MainActor
final class DataModeController: ObservableObject {
    enum Mode: String { case demo, real }

    /// The user's choice, persisted under "dataMode" (launch argument `-dataMode real|demo` overrides).
    @Published private(set) var mode: Mode
    /// Demo time travel inside the flare story (1...14). Test days live in `AppState.experimentDay`.
    @Published private(set) var storyDay: Int = StoryPoint.flareLength
    /// Last real-mode refresh (Health + weather).
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshing = false
    /// Last weather report (real mode), for Settings.
    @Published private(set) var environment: EnvironmentReport?

    private weak var app: AppState?
    private weak var toasts: ToastCenter?
    /// Real-mode flare heads-up (set by `ShellServices`).
    var alerts: FlareAlerts?
    private var access: DeviceAccess?
    private var saved = RealStore.loadSaved()
    /// Every episode received from the watch (30 days), mirrored from `RealStore`.
    private var received = RealStore.loadEpisodes()
    private var bag = Set<AnyCancellable>()
    private var lastWeatherFetch: Date?

    static let modeKey = "dataMode"

    /// The mode at launch (used by `AppState.init` so real mode never flashes demo data).
    static var launchMode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .demo
    }

    /// Real-mode dataset from what is stored on the phone (no network, no Health query).
    static func storedRealDataset() -> TwinDataset {
        RealDataBuilder.build(episodes: RealStore.loadEpisodes(), saved: RealStore.loadSaved())
    }

    init() {
        mode = Self.launchMode
        environment = saved.environment
    }

    func attach(_ app: AppState, toasts: ToastCenter, watch: WatchLink, access: DeviceAccess) {
        self.app = app
        self.toasts = toasts
        self.access = access

        // Time travel (Test screen, tour, Settings) always means the demo story.
        app.$experimentDay
            .dropFirst()
            .sink { [weak self] day in
                guard let self else { return }
                self.storyDay = StoryPoint.flareLength
                if day != nil, self.mode == .real { self.setMode(.demo, rebuild: false) }
            }
            .store(in: &bag)

        // Keep real-mode edits made by other screens (Claude's case file, the running test), and
        // re-apply today's live watch episodes when the demo story is regenerated.
        app.$dataset
            .dropFirst()
            .sink { [weak self] d in self?.datasetDidChange(d) }
            .store(in: &bag)

        watch.onEpisodes = { [weak self] episodes in self?.receive(episodes) }

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, self.mode == .real else { return }
                Task { await self.refreshReal() }
            }
            .store(in: &bag)

        // Launch arguments for demo time travel always mean the demo story.
        let storyArg = UserDefaults.standard.integer(forKey: "storyDay")
        if app.experimentDay != nil || storyArg > 0, mode == .real { setMode(.demo, rebuild: false) }

        if mode == .real {
            if app.dataset.isDemo { app.update { $0 = Self.storedRealDataset() } }
            Task { await refreshReal() }
        } else {
            if app.experimentDay == nil, (1..<StoryPoint.flareLength).contains(storyArg) {
                // `-storyDay N`: start on day N of the flare story.
                travel(to: .flare(storyArg))
            }
            applyLiveOverlay(to: app.dataset)
        }
    }

    // MARK: Mode

    func setMode(_ new: Mode, rebuild: Bool = true) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.modeKey)
        guard rebuild, let app else { return }
        switch new {
        case .real:
            app.update { $0 = RealDataBuilder.build(episodes: received, saved: saved) }
            Task { await refreshReal(force: true) }
        case .demo:
            storyDay = StoryPoint.flareLength
            app.setExperimentDay(nil)
        }
    }

    /// Re-reads Apple Health and the weather (weather at most every 10 minutes unless forced).
    func refreshReal(force: Bool = false) async {
        guard mode == .real, let access, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await access.refresh()

        async let healthDays = access.healthReader.days(RealDataBuilder.windowDays)
        let needsWeather = force || lastWeatherFetch.map { Date().timeIntervalSince($0) > 600 } ?? true
        var report: EnvironmentReport?
        if needsWeather, let coordinate = await access.currentCoordinate() {
            report = try? await OpenMeteoClient().report(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                                       pastDays: RealDataBuilder.windowDays - 1)
            if report != nil { lastWeatherFetch = Date() }
        }
        let health = await healthDays

        if !health.isEmpty {
            saved.health = health.map { day, h in
                RealSaved.HealthEntry(day: day, sleepHours: h.sleepHours, wakeUps: h.wakeUps, hrvMs: h.hrvMs,
                                      restingHR: h.restingHR, workoutMinutes: h.workoutMinutes)
            }.sorted { $0.day < $1.day }
        }
        if let report {
            saved.environment = report
            environment = report
        }
        RealStore.save(saved)
        lastRefresh = Date()
        guard mode == .real, let app, !app.dataset.isDemo else { return }
        let rebuilt = RealDataBuilder.build(episodes: received, saved: saved)
        if rebuilt != app.dataset { app.update { $0 = rebuilt } }
        alerts?.check(app.dataset)
    }

    // MARK: Inputs

    /// Watch episodes arrived (contract: transferUserInfo ["kind": "episodes", "data": ...]).
    private func receive(_ episodes: [ScratchEpisode]) {
        received = RealStore.storeEpisodes(episodes)
        guard let app else { return }
        let shown = Set(app.dataset.episodes.map(\.id))
        let mergeable = mode == .real ? episodes : episodes.filter { isLiveToday($0) || shown.contains($0.id) }
        guard !mergeable.isEmpty else { return }
        var added = 0
        app.update { added = EpisodeMerge.apply(mergeable, to: &$0) }
        if mode == .real { alerts?.check(app.dataset) }
        if added > 0 {
            Haptics.soft()
            toasts?.show(added == 1 ? "New scratch episode from your watch" : "\(added) scratch episodes from your watch",
                         mood: .info, symbol: "applewatch")
        }
    }

    /// Called after the quick-tag sheet saved exposures into today.
    func didTag(_ exposures: [Exposure]) {
        guard mode == .real, !exposures.isEmpty else { return }
        saved.tags += exposures
        let cutoff = Date().addingTimeInterval(-60 * 86_400)
        saved.tags = saved.tags.filter { $0.day > cutoff }
        RealStore.save(saved)
    }

    private func datasetDidChange(_ d: TwinDataset) {
        if mode == .real, !d.isDemo {
            if d.caseFile != saved.caseFile || d.experiment != saved.experiment {
                saved.caseFile = d.caseFile
                saved.experiment = d.experiment
                RealStore.save(saved)
            }
        } else if mode == .demo {
            applyLiveOverlay(to: d)
        }
    }

    private func isLiveToday(_ e: ScratchEpisode) -> Bool {
        e.source == .live && e.label != .rejected && Calendar.current.isDateInToday(e.start)
    }

    /// Demo mode: today's live watch episodes stay on top of whatever story day is shown.
    private func applyLiveOverlay(to d: TwinDataset) {
        let shown = Set(d.episodes.map(\.id))
        let missing = received.filter { isLiveToday($0) && !shown.contains($0.id) }
        guard !missing.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let app = self?.app, app.dataset.isDemo else { return }
            app.update { EpisodeMerge.apply(missing, to: &$0) }
        }
    }

    // MARK: Time travel

    /// Where the demo timeline currently is.
    var position: StoryPoint {
        if let d = app?.experimentDay { return .test(d) }
        return .flare(storyDay)
    }

    /// Demo time travel to any day of the story or the test.
    func travel(to point: StoryPoint) {
        guard let app else { return }
        if mode == .real { setMode(.demo, rebuild: false) }
        switch point {
        case .test(let d):
            app.setExperimentDay(d)
        case .flare(let d):
            if d >= StoryPoint.flareLength {
                app.setExperimentDay(nil)
            } else {
                if app.experimentDay != nil || !app.dataset.isDemo { app.setExperimentDay(nil) }
                let story = StoryClock.flareStory(day: d)
                app.update { $0 = story }
            }
            storyDay = min(max(d, 1), StoryPoint.flareLength)
        }
    }
}
