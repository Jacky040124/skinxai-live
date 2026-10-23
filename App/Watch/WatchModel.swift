import SwiftUI
import WatchKit
import EczemaKit

/// What the ring shows for today.
struct TodaySummary: Equatable {
    var minutes: Double
    var episodes: Int
    var intense: Int
    /// The user's usual minutes per day.
    var usual: Double
    var isDemo: Bool

    var ratio: Double { usual > 0 ? minutes / usual : 0 }
    /// The ring is full at an hour of scratching (or 3x the usual, if that is more).
    var scale: Double { max(60, usual * 3) }
    var progress: Double { min(1, minutes / scale) }
    var usualMark: Double { min(1, usual / scale) }
    var aboveUsual: Bool { minutes > usual + 0.5 }
}

/// "Were you scratching?" for one episode.
struct ScratchAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Found by live detection (real sensor, or the simulator's scripted one).
        case live(EpisodeSource)
        /// The demo moment (`-screen prompt`, or a long press on the ring).
        case demo(ScratchEpisode)
    }
    let id: UUID
    let start: Date
    var windows: [WindowFeatures]
    var meanHz: Double
    let kind: Kind
}

/// Episodes of one day for the Recent page.
struct EpisodeDay: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let episodes: [ScratchEpisode]
}

/// Watch app state.
///
/// Launch arguments (scripts/watchshot): `-screen ring|prompt|recent`, `-expDay N` (demo story day of
/// the 10-day test, like the phone), `-live 1` (start live detection right away).
@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    enum Screen: String { case ring, prompt, recent }
    enum Page: Hashable { case ring, recent }
    enum LiveState: Equatable {
        case off
        case starting
        case on(since: Date, backing: LiveMonitor.Backing)
        var isOn: Bool { if case .on = self { return true } else { return false } }
    }
    /// One analysed window, for the live strip.
    struct LiveTick: Identifiable, Equatable {
        let id: Int
        let level: Double
        let scratch: Bool
    }

    @Published var page: Page = .ring
    @Published private(set) var alert: ScratchAlert?
    @Published private(set) var live: LiveState = .off
    @Published private(set) var ticks: [LiveTick] = []
    @Published private(set) var dataset: TwinDataset
    /// Real episodes on this watch (live + recorded), persisted.
    @Published private(set) var realEpisodes: [ScratchEpisode]
    /// In-memory episodes: demo/simulated ones, and confirmed live episodes that are still going.
    @Published private(set) var extraEpisodes: [ScratchEpisode] = []
    @Published private(set) var personal: ScratchModel
    @Published private(set) var flash: WatchFlash?
    /// What the ring showed when the alert came up; it resumes from here when the alert closes.
    @Published private(set) var ringResume: TodaySummary?

    private let store = WatchStore()
    private let link = PhoneLink.shared
    private let monitor = LiveMonitor()
    private let recorder = BackgroundRecorder()
    private var pendingLabels: [UUID: EpisodeLabel] = [:]
    private var experimentDay: Int?
    private var tickCounter = 0
    private var analyzing = false
    private var flashTask: Task<Void, Never>?
    private var alertTimeout: Task<Void, Never>?
    private var builtFor = Date()

    init() {
        let defaults = UserDefaults.standard
        experimentDay = defaults.string(forKey: "expDay").flatMap(Int.init).map { min(max($0, 1), 10) }
        dataset = DemoData.make(today: Date(), experimentDay: experimentDay)
        realEpisodes = []
        personal = ScratchModel()
        realEpisodes = store.episodes
        personal = store.model

        monitor.onEvent = { [weak self] event in self?.handle(event) }
        link.onActivated = { [weak self] in self?.syncToPhone() }
        link.onFailed = { [weak self] ids in self?.store.markUnsent(ids) }
        link.activate()

        if let raw = defaults.string(forKey: "screen"), let screen = Screen(rawValue: raw) {
            switch screen {
            case .ring: page = .ring
            case .recent: page = .recent
            case .prompt:
                page = .ring
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.presentDemoAlert()
                }
            }
        }
        if defaults.bool(forKey: "live") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.toggleLive()
            }
        }
    }

    // MARK: - What the screens read

    private var calendar: Calendar { .current }

    /// Real, counted episodes (persisted + confirmed ones still going).
    private var realCounted: [ScratchEpisode] {
        (realEpisodes + extraEpisodes.filter { $0.source != .demo }).filter { $0.label != .rejected }
    }

    /// Real data wins for today when there is any (same rule as the phone); otherwise the demo story.
    var usesRealData: Bool { realCounted.contains { calendar.isDateInToday($0.start) } }

    var today: TodaySummary {
        if usesRealData {
            let list = realCounted.filter { calendar.isDateInToday($0.start) }
            return TodaySummary(minutes: list.minutes, episodes: list.count, intense: list.filter(\.intense).count,
                                usual: realUsual, isDemo: false)
        }
        let extra = extraEpisodes.filter { $0.source == .demo && $0.label != .rejected && calendar.isDateInToday($0.start) }
        let day = dataset.today
        return TodaySummary(minutes: (day?.scratchMinutes ?? 0) + extra.minutes,
                            episodes: (day?.episodeCount ?? 0) + extra.count,
                            intense: (day?.intenseCount ?? 0) + extra.filter(\.intense).count,
                            usual: dataset.baselineMinutesPerDay, isDemo: true)
    }

    /// Median of the previous days with real data (needs 3), else the story's calm baseline.
    private var realUsual: Double {
        let todayStart = calendar.startOfDay(for: Date())
        let past = Dictionary(grouping: realCounted.filter { $0.start < todayStart }) { calendar.startOfDay(for: $0.start) }
            .values.map(\.minutes).sorted()
        guard past.count >= 3 else { return dataset.baselineMinutesPerDay }
        let mid = past.count / 2
        return past.count % 2 == 0 ? (past[mid - 1] + past[mid]) / 2 : past[mid]
    }

    /// The latest episodes (newest first, at most `limit`), grouped by day.
    func recentDays(limit: Int = 24) -> [EpisodeDay] {
        let now = Date()
        let list: [ScratchEpisode]
        if usesRealData {
            list = realCounted
        } else {
            list = dataset.episodes.filter { $0.start <= now }
                + extraEpisodes.filter { $0.source == .demo && $0.label != .rejected }
        }
        let skip = max(0, UserDefaults.standard.integer(forKey: "recentSkip"))   // `-recentSkip N` (screenshots)
        let latest = list.sorted { $0.start > $1.start }.dropFirst(skip).prefix(limit)
        var days: [EpisodeDay] = []
        for e in latest {
            let day = calendar.startOfDay(for: e.start)
            if let last = days.last, last.day == day {
                days[days.count - 1] = EpisodeDay(day: day, episodes: last.episodes + [e])
            } else {
                days.append(EpisodeDay(day: day, episodes: [e]))
            }
        }
        return days
    }

    /// Minutes of scratching on a day, the same way the ring counts today.
    func minutes(on day: Date) -> Double {
        if calendar.isDateInToday(day) { return today.minutes }
        if usesRealData { return realCounted.filter { calendar.isDate($0.start, inSameDayAs: day) }.minutes }
        let extra = extraEpisodes.filter { $0.source == .demo && $0.label != .rejected && calendar.isDate($0.start, inSameDayAs: day) }
        return (dataset.day(day, calendar: calendar)?.scratchMinutes ?? 0) + extra.minutes
    }

    var answersLearned: Int { personal.answerCount }

    /// All-day recorder state for the status card.
    enum RecorderStatus: Equatable { case unavailable, denied, off, on(until: Date) }
    var recorderStatus: RecorderStatus {
        guard BackgroundRecorder.isAvailable else { return .unavailable }
        if BackgroundRecorder.isDenied { return .denied }
        if let until = store.book.recorderArmedUntil, until > Date() { return .on(until: until) }
        return .off
    }

    /// When episodes last went to the iPhone, and how many are still waiting.
    var lastSentAt: Date? { store.book.lastSentAt }
    var waitingForPhone: Int { store.unsent(excluding: alert?.id).count }

    /// Forget what the model learned (back to the hand-set weights).
    func resetLearning() {
        var m = personal
        m.reset()
        withAnimation(Twin.Motion.spring) { personal = m }
        store.setModel(m)
        monitor.update(model: m)
        WatchHaptic.play(.directionDown)
    }

    // MARK: - Lifecycle

    func appBecameActive() {
        if !calendar.isDate(builtFor, equalTo: Date(), toGranularity: .hour) {
            builtFor = Date()
            withAnimation(Twin.Motion.spring) {
                dataset = DemoData.make(today: Date(), experimentDay: experimentDay)
            }
        }
        if let until = recorder.armIfNeeded(armedUntil: store.book.recorderArmedUntil) {
            store.setRecorderArmedUntil(until)
        }
        Task { await analyzeRecordings(maxSlices: 12) }
        syncToPhone()
        scheduleBackgroundRefresh()
    }

    /// Reads the all-day recording up to now and adds what it finds.
    func analyzeRecordings(maxSlices: Int) async {
        guard !analyzing, BackgroundRecorder.isAvailable else { return }
        analyzing = true
        defer { analyzing = false }
        let from = store.book.analyzedThrough ?? Date().addingTimeInterval(-BackgroundRecorder.recordingLength)
        guard let result = await recorder.analyze(from: from, model: personal, maxSlices: maxSlices) else { return }
        store.setAnalyzedThrough(result.through)
        let added = store.add(result.episodes.map(\.episode))
        guard !added.isEmpty else { return }
        let ids = Set(added.map(\.id))
        for d in result.episodes where ids.contains(d.id) { store.setEvidence(d.windows, for: d.id) }
        withAnimation(Twin.Motion.spring) { realEpisodes = store.episodes }
        syncToPhone()
    }

    func scheduleBackgroundRefresh() {
        guard BackgroundRecorder.isAvailable else { return }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(45 * 60), userInfo: nil) { _ in }
    }

    // MARK: - Live detection

    func toggleLive() {
        switch live {
        case .off:
            WatchHaptic.play(.start)
            withAnimation(Twin.Motion.spring) { live = .starting }
            Task { await monitor.start(model: personal, lastAlert: nil) }
        case .starting, .on:
            WatchHaptic.play(.stop)
            monitor.stop()
        }
    }

    private func handle(_ event: LiveMonitor.Event) {
        switch event {
        case let .started(backing, since):
            withAnimation(Twin.Motion.spring) { live = .on(since: since, backing: backing) }
        case let .backingChanged(backing):
            if case let .on(since, _) = live { live = .on(since: since, backing: backing) }
        case .stopped:
            withAnimation(Twin.Motion.spring) {
                live = .off
                ticks = []
            }
        case let .window(w):
            tickCounter += 1
            let motion = min(1, w.features.strength / 0.4) * 0.5
            let tick = LiveTick(id: tickCounter, level: max(w.probability, w.features.moving ? motion : 0), scratch: w.isScratch)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                ticks.append(tick)
                if ticks.count > 12 { ticks.removeFirst(ticks.count - 12) }
            }
        case let .episodeStarted(start):
            guard start.shouldAlert, alert == nil else { return }
            let source: EpisodeSource = monitor.hasAccelerometer ? .live : .demo
            show(ScratchAlert(id: start.id, start: start.start, windows: start.windows, meanHz: start.meanHz, kind: .live(source)))
        case let .episodeEnded(detected):
            episodeEnded(detected)
        }
    }

    private func episodeEnded(_ detected: DetectedEpisode) {
        var e = detected.episode
        if let label = pendingLabels.removeValue(forKey: e.id) { e.label = label }
        extraEpisodes.removeAll { $0.id == e.id }                 // drop the provisional copy
        if e.source == .demo {
            if e.label != .rejected { withAnimation(Twin.Motion.spring) { extraEpisodes.append(e) } }
            return
        }
        store.add([e])
        store.setEvidence(detected.windows, for: e.id)
        withAnimation(Twin.Motion.spring) { realEpisodes = store.episodes }
        syncToPhone()
    }

    // MARK: - The scratch alert

    /// The demo moment: the real detector scores a synthetic scratch, so the answer teaches the
    /// personal model with honest features; a "Yes" adds the episode to today.
    func presentDemoAlert() {
        guard alert == nil else { return }
        let now = Date()
        var signal = SyntheticMotion(start: now.timeIntervalSinceReferenceDate - 9, seed: UInt64(now.timeIntervalSince1970))
        signal.scratch(7, hz: 4.3, amplitude: 0.24)
        let found = ScratchDetector.episodes(in: signal.samples, model: personal, source: .demo).first
        let episode = ScratchEpisode(start: now.addingTimeInterval(-74), end: now.addingTimeInterval(-2),
                                     meanHz: found?.episode.meanHz ?? 4.3, meanRMS: found?.episode.meanRMS ?? 0.18,
                                     intense: false, source: .demo)
        show(ScratchAlert(id: episode.id, start: episode.start, windows: found?.windows ?? [], meanHz: episode.meanHz,
                          kind: .demo(episode)))
    }

    private func show(_ a: ScratchAlert) {
        page = .ring
        ringResume = today
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { alert = a }
        WatchHaptic.scratchAlert()
        alertTimeout?.cancel()
        alertTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, self.alert?.id == a.id else { return }
            withAnimation(Twin.Motion.spring) { self.alert = nil }
            self.syncToPhone()                                     // unanswered: send it unlabeled
        }
    }

    /// The user's answer: teach the model, dismiss, then count it (so the ring is on screen when
    /// the number ticks up).
    func answer(_ scratching: Bool) {
        guard let a = alert else { return }
        alertTimeout?.cancel()

        var m = personal
        m.learn(from: store.evidence(for: a.id) ?? a.windows, scratching: scratching)
        personal = m
        store.setModel(m)
        monitor.update(model: m)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { alert = nil }

        let label: EpisodeLabel = scratching ? .confirmed : .rejected
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self else { return }
            switch a.kind {
            case var .demo(e):
                if scratching {
                    e.label = .confirmed
                    self.extraEpisodes.append(e)
                }
            case let .live(source):
                self.apply(label, to: a, source: source)
            }
            self.showFlash(scratching ? .logged : .ignored)
            if scratching { WatchHaptic.play(.success) }
            self.syncToPhone()
        }
    }

    private func apply(_ label: EpisodeLabel, to a: ScratchAlert, source: EpisodeSource) {
        if store.episode(a.id) != nil {
            store.setLabel(label, for: a.id)
            realEpisodes = store.episodes
        } else if let i = extraEpisodes.firstIndex(where: { $0.id == a.id }) {
            extraEpisodes[i].label = label
        } else {
            // Still going: count what we have so far, and label it when it ends.
            pendingLabels[a.id] = label
            if label == .confirmed {
                let rms = a.windows.isEmpty ? 0.18 : a.windows.map(\.strength).reduce(0, +) / Double(a.windows.count)
                extraEpisodes.append(ScratchEpisode(id: a.id, start: a.start, end: max(Date(), a.start.addingTimeInterval(3)),
                                                    meanHz: a.meanHz, meanRMS: rms, intense: rms >= 0.35,
                                                    source: source, label: .confirmed))
            }
        }
    }

    private func showFlash(_ f: WatchFlash) {
        flashTask?.cancel()
        withAnimation(Twin.Motion.spring) { flash = f }
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(Twin.Motion.spring) { self?.flash = nil }
        }
    }

    // MARK: - iPhone

    /// Sends real, not-rejected episodes the phone hasn't had yet (waits for an open question).
    func syncToPhone() {
        let pending = store.unsent(excluding: alert?.id)
        guard !pending.isEmpty else { return }
        if link.send(pending) { store.markSent(pending.map(\.id)) }
    }
}

extension Array where Element == ScratchEpisode {
    var minutes: Double { reduce(0) { $0 + $1.duration } / 60 }
}
