import SwiftUI
import EczemaKit

/// Drives the Insight reveal: thinking → summary typing → suspect cards by rank → the rest.
/// Lives for the whole launch (screens are rebuilt on every tab switch), so the reveal plays once
/// per launch and keeps going if you switch tabs halfway. "Re-run analysis" plays it again and, when an
/// API key is set, asks the live model first: for at most `liveLimit` seconds, and the person can stop
/// waiting at any time.
///
/// The bundled analysis is Douglas's. It only stands in where it is true: his demo story on day 14 or
/// during the test (`bundledAllowed`, decided by the screen). Real data and the earlier story days never
/// get it; they get an honest "add your key" / "offline" state instead.
@MainActor
final class InsightSession: ObservableObject {
    static let shared = InsightSession()

    enum Phase: Int, Comparable {
        case idle, thinking, typing, cards, done
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    /// Why the last re-run didn't bring a new live analysis.
    enum Miss: Equatable {
        /// No API key, and no bundled analysis that fits this data.
        case needsKey
        /// The live call failed; the reason says how (offline, model unavailable, too slow).
        case fellBack(InsightOutcome.BundledReason)
        /// The person stopped waiting for the live call.
        case stopped
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusLine = ""
    /// Words of the summary typed so far.
    @Published private(set) var typedWords = 0
    /// Suspect cards on screen so far.
    @Published private(set) var shownSuspects = 0
    /// A live model call is in flight.
    @Published private(set) var isAsking = false
    /// The live call has been running for `slowAfter` seconds: offer a way out.
    @Published private(set) var isSlow = false
    /// Why the last re-run fell short (nil after a live answer, or before any re-run).
    @Published private(set) var miss: Miss?

    /// Hard limit for a live call on screen; then the bundled analysis (or an honest note) takes over.
    static let liveLimit: TimeInterval = 20
    /// When the thinking card starts offering "use the bundled analysis" / "stop waiting".
    static let slowAfter: TimeInterval = 6

    private var task: Task<Void, Never>?

    // MARK: Intents

    /// The Insight screen appeared: reveal once per launch.
    func appear(app: AppState, reduceMotion: Bool, bundledAllowed: Bool) {
        // Real data never keeps the bundled analysis: it describes Douglas's story, not you (an older
        // build could have saved it there).
        if !app.dataset.isDemo, app.dataset.caseFile?.isBundled == true { app.update { $0.caseFile = nil } }
        refreshKeyState()
        guard phase == .idle else { return }
        #if DEBUG
        DebugHooks.prepare(app: app)
        #endif
        guard app.dataset.caseFile != nil else {
            phase = .done
            #if DEBUG
            if DebugHooks.autoRerun {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                    self?.rerun(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
                }
            }
            #endif
            return
        }
        start(app: app, reduceMotion: reduceMotion, key: nil, bundledAllowed: bundledAllowed)
    }

    /// The demo tour: play the bundled reveal again from the start (no network), even if it already ran.
    func replay(app: AppState, reduceMotion: Bool, bundledAllowed: Bool) {
        task?.cancel()
        isAsking = false
        isSlow = false
        miss = nil
        if bundledAllowed, app.dataset.caseFile?.isBundled != true {
            app.update { $0.caseFile = InsightService.bundledCaseFile(for: $0) }
        }
        guard app.dataset.caseFile != nil else { phase = .done; return }
        start(app: app, reduceMotion: reduceMotion, key: nil, bundledAllowed: bundledAllowed)
    }

    /// "Re-run analysis" / "Analyze what I have": the live model when a key is set. Without one: the
    /// bundled analysis again where it fits the data, else an honest "add your key" (nothing is replayed).
    func rerun(app: AppState, reduceMotion: Bool, bundledAllowed: Bool) {
        Haptics.soft()
        let key = Self.apiKey()
        if key == nil {
            guard bundledAllowed else {
                Haptics.warning()
                withAnimation(Twin.Motion.spring) { miss = .needsKey }
                return
            }
            miss = nil
            if app.dataset.caseFile?.isBundled != true {
                app.update { $0.caseFile = InsightService.bundledCaseFile(for: $0) }
            }
        }
        start(app: app, reduceMotion: reduceMotion, key: key, bundledAllowed: bundledAllowed)
    }

    /// A tap on the thinking card: skip to the end, or stop waiting for the live call.
    func finishNow(app: AppState) {
        if isAsking { stopWaiting(app: app); return }
        guard phase > .idle, phase < .done else { return }
        Haptics.tap()
        task?.cancel()
        revealAll(app)
    }

    /// Stop waiting for the live model: keep what is on screen (in the demo story, the bundled analysis)
    /// and show all of it at once.
    func stopWaiting(app: AppState) {
        guard isAsking else { return }
        Haptics.tap()
        task?.cancel()
        withAnimation(Twin.Motion.spring) {
            isAsking = false
            isSlow = false
            miss = .stopped
        }
        revealAll(app)
    }

    /// Settings may have added a key since the last try: drop a stale "add your key".
    func refreshKeyState() {
        if miss == .needsKey, Self.apiKey() != nil { withAnimation(Twin.Motion.spring) { miss = nil } }
    }

    // MARK: The reveal

    private func revealAll(_ app: AppState) {
        withAnimation(Twin.Motion.spring) {
            typedWords = Int.max
            shownSuspects = app.dataset.caseFile?.suspects.count ?? 0
            phase = .done
        }
    }

    private static func apiKey() -> String? {
        #if DEBUG
        if let fake = DebugHooks.testKey { return fake }
        #endif
        return InsightCredentials.apiKey()
    }

    private func start(app: AppState, reduceMotion: Bool, key: String?, bundledAllowed: Bool) {
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(app: app, reduceMotion: reduceMotion, key: key, bundledAllowed: bundledAllowed)
        }
    }

    /// Sleeps; false when the reveal was cancelled (re-run tapped).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    private func run(app: AppState, reduceMotion: Bool, key: String?, bundledAllowed: Bool) async {
        let model = InsightCredentials.model()
        let dataset = app.dataset
        let days = key != nil ? dataset.days.count
            : dataset.caseFile.map { InsightService.windowDays($0) } ?? dataset.days.count
        let lines = ["Reading \(days) days of scratching, sleep and weather…",
                     "Checking what changed 1–3 days before each jump…",
                     "Ranking suspects…"]
        let waiting = ["Asking Claude to explain the numbers…", "Weighing the 1–3 day lag…",
                       "Double-checking the dates…", "Writing your case file…"]

        // 1. Thinking.
        withAnimation(.easeOut(duration: 0.18)) { shownSuspects = 0 }
        withAnimation(Twin.Motion.spring) {
            phase = .thinking
            typedWords = 0
            statusLine = lines[0]
        }
        let ticker = Task { [weak self] in
            var i = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: i < lines.count ? 730_000_000 : 2_200_000_000)
                guard !Task.isCancelled, let self else { return }
                let next = i < lines.count ? lines[i] : waiting[min(i - lines.count, waiting.count - 1)]
                if next != self.statusLine { withAnimation(Twin.Motion.spring) { self.statusLine = next } }
                i += 1
            }
        }
        defer { ticker.cancel() }

        let started = Date()
        if let key {
            withAnimation(Twin.Motion.spring) {
                isAsking = true
                isSlow = false
            }
            let slowTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.slowAfter * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isAsking else { return }
                withAnimation(Twin.Motion.spring) { self.isSlow = true }
            }
            let outcome = await liveOutcome(dataset: dataset, key: key, model: model)
            slowTimer.cancel()
            // Stopped by the person: `stopWaiting` already settled what stays on screen.
            guard !Task.isCancelled else { return }
            withAnimation(Twin.Motion.spring) {
                isAsking = false
                isSlow = false
            }
            if outcome.isLive {
                miss = nil
                app.update { $0.caseFile = outcome.caseFile }
            } else {
                miss = .fellBack(outcome.bundledReason ?? .failed)
                // Only where the bundled analysis is true; elsewhere keep what is there (or nothing).
                if bundledAllowed, app.dataset.caseFile?.isBundled != true {
                    app.update { $0.caseFile = outcome.caseFile }
                }
                Haptics.warning()
            }
            // Nothing on file to reveal (your own data, or the story before day 14): the honest state shows
            // now, with no "thinking" left running behind it.
            if app.dataset.caseFile == nil {
                ticker.cancel()
                withAnimation(Twin.Motion.spring) { phase = .done }
                return
            }
        }
        let minimum = reduceMotion ? 0.6 : 2.2
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < minimum, !(await pause(minimum - elapsed)) { return }
        ticker.cancel()

        guard let caseFile = app.dataset.caseFile else {
            withAnimation(Twin.Motion.spring) { phase = .done }
            return
        }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) {
                typedWords = Int.max
                shownSuspects = caseFile.suspects.count
                phase = .done
            }
            return
        }

        // 2. The summary types out, word by word.
        withAnimation(Twin.Motion.spring) { phase = .typing }
        Haptics.soft()
        if !(await pause(0.25)) { return }
        let words = caseFile.summary.split(separator: " ")
        for (i, word) in words.enumerated() {
            typedWords = i + 1
            var delay = 0.03 + Double(min(word.count, 10)) * 0.0035
            if let last = word.last {
                if ".!?".contains(last) { delay += 0.17 } else if ",;:".contains(last) { delay += 0.07 }
            }
            if !(await pause(delay)) { return }
        }
        typedWords = Int.max

        // 3. Suspect cards fly in by rank.
        if !(await pause(0.3)) { return }
        withAnimation(Twin.Motion.spring) { phase = .cards }
        for i in caseFile.suspects.indices {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { shownSuspects = i + 1 }
            if !(await pause(0.15)) { return }
        }

        // 4. The rest of the case file, once the #1 evidence timeline has landed its "+2 DAYS" (its arc
        //    draws 0.75–1.65 s after the card arrives): the note and the test follow the evidence, and the
        //    hero arc never shares its frames with a big insertion below.
        let timeline = caseFile.suspects.first.map { $0.startedOn != nil && $0.flareOn != nil } ?? false
        if !(await pause(timeline ? 1.3 : 0.35)) { return }
        withAnimation(Twin.Motion.spring) { phase = .done }
        #if DEBUG
        if key == nil, DebugHooks.autoRerun, !DebugHooks.didAutoRerun, await pause(1.5) {
            DebugHooks.didAutoRerun = true
            rerun(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
        }
        #endif
    }

    private func liveOutcome(dataset: TwinDataset, key: String, model: String) async -> InsightOutcome {
        #if DEBUG
        if let delay = DebugHooks.fakeLiveDelay {
            return await DebugHooks.fakeLive(dataset: dataset, delay: delay, limit: Self.liveLimit)
        }
        #endif
        return await InsightService.analyze(dataset: dataset, apiKey: key, model: model, limit: Self.liveLimit)
    }
}

#if DEBUG
/// Launch arguments for checking paths that need a tap or a key, in Debug builds only:
///   -insightTestKey 1      re-run uses a deliberately invalid key (exercises the live call + fallback)
///   -insightAutoRerun 1    re-run once by itself after the first reveal (or tap "Analyze what I have")
///   -insightRedFlags 1     add a red flag to the case file
///   -insightFakeLive <s>   with -insightTestKey: no network; the "live" answer arrives after <s> seconds and
///                          plans a different test (Stop the scented body wash, 14 days). <s> > 20 = too slow.
///   -insightQA <script>    startTest: tap the pink "Start a test" button once the reveal is done
///                          stopWaiting: tap "Use the bundled analysis" as soon as it shows
enum DebugHooks {
    static var testKey: String? { UserDefaults.standard.bool(forKey: "insightTestKey") ? "invalid-test-key" : nil }
    static var autoRerun: Bool { UserDefaults.standard.bool(forKey: "insightAutoRerun") }
    static var didAutoRerun = false
    static var fakeLiveDelay: Double? {
        let s = UserDefaults.standard.double(forKey: "insightFakeLive")
        return s > 0 ? s : nil
    }
    static var script: String? { UserDefaults.standard.string(forKey: "insightQA") }

    @MainActor static func prepare(app: AppState) {
        if UserDefaults.standard.bool(forKey: "insightRedFlags"), app.dataset.caseFile?.redFlags.isEmpty == true {
            app.update { $0.caseFile?.redFlags = [
                "Your last note says the patches are weeping yellow fluid with honey-coloured crusts, and you feel feverish (38.4 °C). That can be an infection."
            ] }
        }
    }

    /// A pretend live call (no network): waits `delay` seconds, then answers with a live-looking case file.
    static func fakeLive(dataset: TwinDataset, delay: Double, limit: TimeInterval) async -> InsightOutcome {
        let stats = StatsEngine.analyze(dataset.days)
        let bundled = InsightService.bundledCaseFile(for: dataset)
        var live = bundled
        live.id = UUID()
        live.number = bundled.number + 1
        live.createdAt = dataset.today?.day ?? Date()
        live.producedBy = "claude-sonnet-5.5 · live"
        live.summary = "Your scratching jumped about 2 days after you started the new scented body wash, and it stayed high every day since. The air turned dry the next day too, so a clean test is the only way to tell the two apart."
        live.nextExperiment = ExperimentPlan(title: "Stop the scented body wash",
                                             instruction: "Use your old wash for 14 days. Keep food, gym and room humidity the same.",
                                             trigger: .newProduct, lengthDays: 14)
        let answer = await InsightService.withTimeLimit(limit) { () async -> InsightOutcome? in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return Task.isCancelled ? nil : InsightOutcome(caseFile: live, source: .live(model: "anthropic/claude-sonnet-5.5"), stats: stats)
        }
        return (answer ?? nil) ?? InsightOutcome(caseFile: bundled, source: .bundled(.slow), stats: stats)
    }
}
#endif
