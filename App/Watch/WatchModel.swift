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
/// The watch shows what the iPhone shows (`PhoneContext`, sent by the iPhone whenever Settings →
/// Demo story or the demo day changes):
/// - Demo story (the iPhone's default): Douglas's story for the same day, plus today's live
///   episodes from this wrist and confirmed demo-alert episodes on top — the same rule as the
///   iPhone's demo overlay, so a Yes on the watch ticks both numbers up together.
/// - Real data: this wrist's own episodes (live and all-day recording) and its own usual.
///
/// Launch arguments (scripts/watchshot): `-screen ring|prompt|recent`; `-dataMode demo|real`,
/// `-expDay N` (day of the 10-day test), `-storyDay N` (day of the flare story) pin the data like
/// on the iPhone; `-live 1` starts live detection right away.
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
    /// Which data to show: what the iPhone shows, or what the launch arguments pin.
    @Published private(set) var source: PhoneContext
    /// The demo story for `source` (rebuilt when the hour or the iPhone's story changes).
    @Published private(set) var story: TwinDataset { didSet { rebuildDisplay() } }
    /// Real episodes on this watch (live + recorded), persisted.
    @Published private(set) var realEpisodes: [ScratchEpisode] { didSet { rebuildDisplay() } }
    /// In-memory episodes: demo-story ones (the demo alert, the simulator's scripted wrist) and
    /// confirmed live episodes that are still going.
    @Published private(set) var extraEpisodes: [ScratchEpisode] = [] { didSet { rebuildDisplay() } }
    /// Demo story mode: the story with today's live and demo episodes folded in, as on the iPhone.
    @Published private(set) var display: TwinDataset
    @Published private(set) var personal: ScratchModel
    @Published private(set) var flash: WatchFlash?
    /// What the ring showed when the alert came up; it resumes from here when the alert closes.
    @Published private(set) var ringResume: TodaySummary?
    /// Big-screen relay: true = last send arrived, false = failing, nil = not sending.
    @Published private(set) var screenLink: Bool?
    /// Why the last send to the big screen failed (URL error code, HTTP status), or "" when it worked.
    @Published private(set) var screenDetail = ""
    @Published private(set) var screenSent = 0

    private let store = WatchStore()
    private let link = PhoneLink.shared
    private let monitor = LiveMonitor()
    private let recorder = BackgroundRecorder()
    private var pendingLabels: [UUID: EpisodeLabel] = [:]
    /// Demo-story episodes already handed to the iPhone.
    private var demoSent: Set<UUID> = []
    /// The iPhone's data mode as it last told us; nil if it never did (an iPhone app that doesn't
    /// speak the data-mode contract can't tell demo episodes from real ones, so it gets none).
    private var phoneMode: PhoneContext.Mode?
    /// Launch arguments fixed the data (screenshots): the iPhone doesn't change it.
    private let pinned: Bool
    private var tickCounter = 0
    private var analyzing = false
    private var analysisCancel: BackgroundRecorder.Cancel?
    private var flashTask: Task<Void, Never>?
    private var alertTimeout: Task<Void, Never>?
    private var builtFor = Date()

    private static let phoneContextKey = "phone.context"
    /// After an answer the ring is back on screen before the number ticks up (see WatchRootView).
    private static let tickDelay: Duration = .milliseconds(560)

    init() {
        let defaults = UserDefaults.standard
        let launch = Self.launchContext(defaults.volatileDomain(forName: UserDefaults.argumentDomain))
        let stored = defaults.dictionary(forKey: Self.phoneContextKey).flatMap(PhoneContext.init)
        let source = launch ?? stored ?? .demo
        let story = WatchDemoStory.dataset(for: source)
        pinned = launch != nil
        phoneMode = stored?.mode
        self.source = source
        self.story = story
        display = story
        realEpisodes = []
        personal = ScratchModel()
        realEpisodes = store.episodes
        personal = store.model
        rebuildDisplay()

        monitor.onEvent = { [weak self] event in self?.handle(event) }
        LiveStreamer.shared.onStatus = { [weak self] status in
            guard let self, self.live != .off else { return }
            if self.screenDetail != status.detail { self.screenDetail = status.detail }
            if self.screenSent != status.sent { self.screenSent = status.sent }
            guard self.screenLink != status.ok else { return }
            withAnimation(Twin.Motion.spring) { self.screenLink = status.ok }
        }
        link.onActivated = { [weak self] in self?.syncToPhone() }
        link.onFailed = { [weak self] ids in self?.store.markUnsent(ids) }
        link.onContext = { [weak self] context in self?.receive(context) }
        link.activate()
        if let heard = link.lastContext { receive(heard) }

        if let raw = defaults.string(forKey: "screen"), let screen = Screen(rawValue: raw) {
            switch screen {
            case .ring: page = .ring
            case .recent: page = .recent
            case .prompt:
                page = .ring
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.presentDemoAlert(evenWithRealData: true)
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

    /// `-dataMode`, `-expDay`, `-storyDay`; demo time travel always means the demo story (like on
    /// the iPhone). nil without any of them.
    private static func launchContext(_ args: [String: Any]) -> PhoneContext? {
        let mode = (args["dataMode"] as? String).flatMap { PhoneContext.Mode(rawValue: $0.lowercased()) }
        let exp = (args["expDay"] as? String).flatMap(Int.init)
        let day = (args["storyDay"] as? String).flatMap(Int.init)
        guard mode != nil || exp != nil || day != nil else { return nil }
        let travels = (exp ?? 0) > 0 || (day ?? 0) > 0
        return PhoneContext(mode: travels ? .demo : (mode ?? .demo), expDay: exp, storyDay: day, storyAt: nil)
    }

    // MARK: - What the screens read

    private var calendar: Calendar { .current }

    var showsDemoStory: Bool { source.mode == .demo }

    /// Real, counted episodes (persisted + confirmed ones still going).
    private var realCounted: [ScratchEpisode] {
        (realEpisodes + extraEpisodes.filter { $0.source != .demo }).filter { $0.label != .rejected }
    }

    /// Today's episodes the demo story gets on top, the same ones the iPhone adds: live ones from
    /// this wrist and confirmed demo-story ones (never the all-day recording's).
    private var overlay: [ScratchEpisode] {
        (realEpisodes + extraEpisodes)
            .filter { ($0.source == .live || $0.source == .demo) && $0.label != .rejected && calendar.isDateInToday($0.start) }
    }

    private func rebuildDisplay() {
        guard source.mode == .demo else { return }
        var d = story
        EpisodeMerge.apply(overlay, to: &d, calendar: calendar)
        if d != display { display = d }
    }

    var today: TodaySummary {
        switch source.mode {
        case .demo:
            return Self.summary(of: display, calendar: calendar)
        case .real:
            let list = realCounted.filter { calendar.isDateInToday($0.start) }
            return TodaySummary(minutes: list.minutes, episodes: list.count, intense: list.filter(\.intense).count,
                                usual: realUsual, isDemo: false)
        }
    }

    /// Today the way the iPhone's Today screen counts it (minutes from the hours; episodes that
    /// have happened by now).
    private static func summary(of d: TwinDataset, now: Date = Date(), calendar: Calendar) -> TodaySummary {
        guard let day = d.today else {
            return TodaySummary(minutes: 0, episodes: 0, intense: 0, usual: d.baselineMinutesPerDay, isDemo: true)
        }
        let mine = d.episodes.filter { calendar.isDate($0.start, inSameDayAs: day.day) && $0.start <= now && $0.label != .rejected }
        return TodaySummary(minutes: day.scratchMinutes,
                            episodes: mine.isEmpty ? day.episodeCount : mine.count,
                            intense: mine.isEmpty ? day.intenseCount : mine.filter(\.intense).count,
                            usual: d.baselineMinutesPerDay, isDemo: true)
    }

    /// The iPhone's rule: median of the earlier days of the last two weeks that have episodes
    /// (needs 3), else the calm days of the demo story as a starting guess.
    private var realUsual: Double {
        let todayStart = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -13, to: todayStart) else { return Self.startingUsual }
        let past = Dictionary(grouping: realCounted.filter { $0.start >= from && $0.start < todayStart }) { calendar.startOfDay(for: $0.start) }
            .values.map(\.minutes).sorted()
        guard past.count >= 3 else { return Self.startingUsual }
        let mid = past.count / 2
        return max(1, past.count % 2 == 0 ? (past[mid - 1] + past[mid]) / 2 : past[mid])
    }

    private static let startingUsual: Double = {
        let calm = DemoData.flareMinutes.prefix(DemoData.flareStartDay).sorted()
        let mid = calm.count / 2
        return calm.count % 2 == 0 ? (calm[mid - 1] + calm[mid]) / 2 : calm[mid]
    }()

    /// The latest episodes (newest first, at most `limit`), grouped by day.
    func recentDays(limit: Int = 24) -> [EpisodeDay] {
        let now = Date()
        let list: [ScratchEpisode] = switch source.mode {
        case .demo: display.episodes.filter { $0.start <= now && $0.label != .rejected }
        case .real: realCounted
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
        switch source.mode {
        case .demo: display.day(day, calendar: calendar)?.scratchMinutes ?? 0
        case .real: realCounted.filter { calendar.isDate($0.start, inSameDayAs: day) }.minutes
        }
    }

    /// Which part of the demo story is on screen, e.g. "TEST DAY 3 OF 10" (nil for real data).
    var demoStoryDay: String? {
        guard source.mode == .demo else { return nil }
        if let d = source.expDay {
            let length = story.experiment?.plan.lengthDays ?? DemoData.experimentMinutes.count
            return "TEST DAY \(d) OF \(length)"
        }
        if let d = source.storyDay { return "DAY \(d) OF \(DemoData.flareMinutes.count)" }
        return nil
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

    // MARK: - The iPhone's data mode

    private func receive(_ context: PhoneContext) {
        phoneMode = context.mode
        UserDefaults.standard.set(context.dictionary, forKey: Self.phoneContextKey)
        if !pinned, context != source {
            withAnimation(Twin.Motion.spring) {
                source = context
                story = WatchDemoStory.dataset(for: context)
            }
            builtFor = Date()
        }
        syncDemoToPhone()
    }

    // MARK: - Lifecycle

    func appBecameActive() {
        // A fresh hour of the story, like opening the iPhone app again (unless the iPhone said
        // when it built its story today: then both stay on that hour).
        let heldByPhone = source.storyAt.map { calendar.isDateInToday($0) } ?? false
        if !heldByPhone, !calendar.isDate(builtFor, equalTo: Date(), toGranularity: .hour) {
            builtFor = Date()
            withAnimation(Twin.Motion.spring) { story = WatchDemoStory.dataset(for: source) }
        }
        monitor.appBecameActive()
        if let until = recorder.armIfNeeded(armedUntil: store.book.recorderArmedUntil) {
            store.setRecorderArmedUntil(until)
        }
        Task { await analyzeRecordings(.appOpen) }
        syncToPhone()
        scheduleBackgroundRefresh()
    }

    /// Twin left the screen: stop reading the recording (the rest waits) and save.
    func appMovedToBackground() {
        analysisCancel?.cancel()
        Task { await store.flush() }
    }

    /// Background refresh: read a little of the recording, hand new episodes to the iPhone, book
    /// the next refresh, and save before watchOS suspends the app.
    func backgroundRefresh() async {
        await analyzeRecordings(.backgroundRefresh)
        syncToPhone()
        scheduleBackgroundRefresh()
        await store.flush()
    }

    /// The background task is out of time: stop reading (what was read is kept).
    func cancelAnalysis() { analysisCancel?.cancel() }

    /// Reads the all-day recording from where the last run stopped, within `budget`.
    func analyzeRecordings(_ budget: BackgroundRecorder.Budget) async {
        guard !analyzing, BackgroundRecorder.isAvailable else { return }
        analyzing = true
        let cancel = BackgroundRecorder.Cancel()
        analysisCancel = cancel
        defer {
            analyzing = false
            analysisCancel = nil
        }
        let from = store.book.analyzedThrough ?? Date().addingTimeInterval(-BackgroundRecorder.recordingLength)
        guard let result = await recorder.analyze(from: from, model: personal, budget: budget, cancel: cancel) else { return }
        let added = store.addRecorded(result.episodes, analyzedThrough: result.through)
        guard !added.isEmpty else { return }
        withAnimation(Twin.Motion.spring) { realEpisodes = store.episodes }
        syncToPhone()
    }

    func scheduleBackgroundRefresh() {
        guard BackgroundRecorder.isAvailable else { return }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
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
            if case let .on(since, _) = live { withAnimation(Twin.Motion.spring) { live = .on(since: since, backing: backing) } }
        case .stopped:
            withAnimation(Twin.Motion.spring) {
                live = .off
                ticks = []
                screenLink = nil
                screenDetail = ""
                screenSent = 0
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
        if e.source == .demo {
            var extra = extraEpisodes.filter { $0.id != e.id }      // drop the provisional copy
            if e.label != .rejected { extra.append(e) }
            withAnimation(Twin.Motion.spring) { extraEpisodes = extra }
            syncToPhone()
            return
        }
        extraEpisodes.removeAll { $0.id == e.id }                 // drop the provisional copy
        store.add([e])
        store.setEvidence(detected.windows, for: e.id)
        withAnimation(Twin.Motion.spring) { realEpisodes = store.episodes }
        syncToPhone()
    }

    // MARK: - The scratch alert

    /// The long press on the ring asks the demo question (demo story only: in real data mode
    /// the ring is the wearer's own and only real detections ask).
    var canAskDemoQuestion: Bool { source.mode == .demo }

    /// The demo moment: the real detector scores a synthetic scratch, so the answer teaches the
    /// personal model with honest features; a "Yes" adds the episode to today (on the iPhone too).
    /// `evenWithRealData`: `-screen prompt` always opens it (a Yes then teaches but doesn't count).
    func presentDemoAlert(evenWithRealData: Bool = false) {
        guard alert == nil, canAskDemoQuestion || evenWithRealData else { return }
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
            try? await Task.sleep(for: Self.tickDelay)
            guard let self else { return }
            var counted = false
            switch a.kind {
            case var .demo(e):
                if scratching {
                    e.label = .confirmed
                    self.extraEpisodes.append(e)
                    counted = self.showsDemoStory
                }
            case let .live(source):
                self.apply(label, to: a, source: source)
                counted = scratching && (source != .demo || self.showsDemoStory)
            }
            self.showFlash(scratching ? (counted ? .logged : .learned) : .ignored)
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

    /// Sends real, not-rejected episodes the iPhone hasn't had yet (waits for an open question),
    /// then the demo-story ones.
    func syncToPhone() {
        let pending = store.unsent(excluding: alert?.id)
        if !pending.isEmpty, link.send(pending) { store.markSent(pending.map(\.id)) }
        syncDemoToPhone()
    }

    /// Confirmed demo-story episodes go to the iPhone's demo overlay, so both numbers tick up
    /// together. Only to an iPhone that told us it shows the demo story (it keeps them out of its
    /// real data), only once they are final (answered, ended), and only today's.
    private func syncDemoToPhone() {
        guard phoneMode == .demo else { return }
        let ready = extraEpisodes.filter {
            $0.source == .demo && $0.label != .rejected && $0.id != alert?.id && pendingLabels[$0.id] == nil
                && !demoSent.contains($0.id) && calendar.isDateInToday($0.start)
        }
        guard !ready.isEmpty, link.send(ready) else { return }
        demoSent.formUnion(ready.map(\.id))
        store.noteSent()
    }
}

extension Array where Element == ScratchEpisode {
    var minutes: Double { reduce(0) { $0 + $1.duration } / 60 }
}
