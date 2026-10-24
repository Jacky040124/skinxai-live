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
    private weak var toasts: ShellToasts?
    /// Real-mode flare heads-up (set by `ShellServices`).
    var alerts: FlareAlerts?
    private var access: DeviceAccess?
    private var saved = RealStore.loadSaved()
    /// Every episode received from the watch (30 days), mirrored from `RealStore`.
    private var received = RealStore.loadEpisodes()
    private var bag = Set<AnyCancellable>()
    private var lastWeatherFetch: Date?
    /// Demo mode: the hour today's story is revealed through (see `keepStoryOnToday`).
    private var revealedHour = DemoData.storyRevealHour()
    /// Fires at the top of the next hour while the app is open.
    private var clockTimer: Timer?

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

    func attach(_ app: AppState, toasts: ShellToasts, watch: WatchInbox, access: DeviceAccess) {
        self.app = app
        self.toasts = toasts
        self.access = access

        // Time travel (Test screen, tour, Settings) always means the demo story.
        app.$experimentDay
            .dropFirst()
            .sink { [weak self] day in
                guard let self else { return }
                self.storyDay = StoryPoint.flareLength
                // `setExperimentDay` rebuilds the story for the current hour.
                self.revealedHour = DemoData.storyRevealHour()
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

        // "Today" moves on while the app stays open or sleeps in the background: midnight, a new
        // hour, a time-zone change, coming back to the app.
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: center.publisher(for: UIApplication.significantTimeChangeNotification),
                   center.publisher(for: .NSCalendarDayChanged))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.clockDidChange() }
            .store(in: &bag)
        // Before the first frame after the app comes back, so a new day never flashes yesterday.
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.keepStoryOnToday() }
            .store(in: &bag)
        scheduleClockTick()

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
        var next = app.dataset
        let added = EpisodeMerge.apply(mergeable, to: &next)
        // Nothing landed (e.g. the episodes are from a day the data doesn't cover): don't republish.
        if next != app.dataset { app.update { $0 = next } }
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
        guard !missingLive(in: d).isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let app = self.app, app.dataset.isDemo else { return }
            let missing = self.missingLive(in: app.dataset)
            guard !missing.isEmpty else { return }
            var next = app.dataset
            // Publish only a merge that changed something, so this can never loop.
            guard EpisodeMerge.apply(missing, to: &next) > 0 else { return }
            app.update { $0 = next }
        }
    }

    /// Today's live episodes the dataset doesn't show yet and that land on one of its days (a
    /// dataset still on yesterday can't take them: it gets rebuilt for today first).
    private func missingLive(in d: TwinDataset) -> [ScratchEpisode] {
        let shown = Set(d.episodes.map(\.id))
        return received.filter {
            isLiveToday($0) && !shown.contains($0.id) && $0.end > $0.start && EpisodeMerge.covers($0, d, .current)
        }
    }

    // MARK: Clock

    /// Midnight, a new hour, a time-zone change or a return to the app.
    private func clockDidChange() {
        switch mode {
        case .real: Task { await refreshReal() }
        case .demo: keepStoryOnToday()
        }
        scheduleClockTick()
    }

    /// Demo mode: the story's last day is always today, revealed through the current hour.
    /// - A new day rebuilds the story at the same point of the timeline (like a fresh launch).
    /// - A new hour only fills in today's scratching, so tags, Claude's case file and every list
    ///   on screen stay as they are (episodes keep their ids).
    func keepStoryOnToday(now: Date = Date()) {
        guard mode == .demo, let app, app.dataset.isDemo, let shownDay = app.dataset.today?.day else { return }
        let calendar = Calendar.current
        guard calendar.isDate(shownDay, inSameDayAs: now) else {
            travel(to: position, now: now)
            return
        }
        let hour = DemoData.storyRevealHour(at: now, calendar: calendar)
        guard hour != revealedHour else { return }
        revealedHour = hour
        let fresh = StoryClock.dataset(at: position, now: now, calendar: calendar)
        guard let freshToday = fresh.today, calendar.isDate(freshToday.day, inSameDayAs: shownDay) else { return }

        var next = app.dataset
        let last = next.days.count - 1
        next.days[last].scratchMinutesByHour = freshToday.scratchMinutesByHour
        next.days[last].episodeCount = freshToday.episodeCount
        next.days[last].intenseCount = freshToday.intenseCount
        let isToday: (ScratchEpisode) -> Bool = { calendar.isDate($0.start, inSameDayAs: shownDay) }
        var ids: [String: UUID] = [:]
        for e in next.episodes where isToday(e) { ids["\(e.start.timeIntervalSince1970)-\(e.end.timeIntervalSince1970)"] = e.id }
        let todays = fresh.episodes.filter(isToday).map { e -> ScratchEpisode in
            var e = e
            if let id = ids["\(e.start.timeIntervalSince1970)-\(e.end.timeIntervalSince1970)"] { e.id = id }
            return e
        }
        // Live watch episodes come back on top through the live overlay.
        next.episodes = (next.episodes.filter { !isToday($0) } + todays).sorted { $0.start < $1.start }
        if next != app.dataset { app.update { $0 = next } }
    }

    /// QA (`-shellDemo hour`): today's story as it looked `hours` ago, so the next clock check
    /// fills in the hours since.
    func rewindStoryClock(hours: Int, now: Date = Date()) {
        guard mode == .demo, let app else { return }
        let hour = min(max(DemoData.storyRevealHour(at: now) - hours, 0), 23)
        let earlier = StoryClock.dataset(at: position, now: now, reveal: hour)
        app.update { $0 = earlier }
        revealedHour = hour
    }

    /// Re-checks the clock a second after the next full hour (only while the app runs).
    private func scheduleClockTick(now: Date = Date()) {
        clockTimer?.invalidate()
        guard let next = Calendar.current.nextDate(after: now, matching: DateComponents(minute: 0, second: 1),
                                                   matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.clockDidChange() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: Time travel

    /// Where the demo timeline currently is.
    var position: StoryPoint {
        if let d = app?.experimentDay { return .test(d) }
        return .flare(storyDay)
    }

    /// Demo time travel to any day of the story or the test.
    func travel(to point: StoryPoint, now: Date = Date()) {
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
                let story = StoryClock.flareStory(day: d, now: now)
                app.update { $0 = story }
            }
            storyDay = min(max(d, 1), StoryPoint.flareLength)
        }
        revealedHour = DemoData.storyRevealHour(at: now)
    }
}
