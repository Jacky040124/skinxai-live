import SwiftUI
import EczemaKit

/// Drives the Insight reveal: thinking → summary typing → suspect cards by rank → the rest.
/// Lives for the whole launch (screens are rebuilt on every tab switch), so the reveal plays once
/// per launch and keeps going if you switch tabs halfway. "Re-run analysis" plays it again and, when an
/// API key is set, asks the live model first.
@MainActor
final class InsightSession: ObservableObject {
    static let shared = InsightSession()

    enum Phase: Int, Comparable {
        case idle, thinking, typing, cards, done
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusLine = ""
    /// Words of the summary typed so far.
    @Published private(set) var typedWords = 0
    /// Suspect cards on screen so far.
    @Published private(set) var shownSuspects = 0
    /// A live model call is in flight.
    @Published private(set) var isAsking = false
    /// Where the case file on screen came from, for the small print.
    @Published private(set) var source: Source = .bundled(.noKey)

    enum Source: Equatable {
        case live(String)
        case bundled(InsightOutcome.BundledReason)
        var note: String {
            switch self {
            case .live(let model): "Live analysis · \(InsightCredentials.shortName(model))"
            case .bundled(let reason): reason.note
            }
        }
        var isLive: Bool { if case .live = self { return true } else { return false } }
    }

    private var task: Task<Void, Never>?

    /// The Insight screen appeared: reveal once per launch.
    func appear(app: AppState, reduceMotion: Bool) {
        guard phase == .idle else { return }
        #if DEBUG
        DebugHooks.prepare(app: app)
        #endif
        if let cf = app.dataset.caseFile, !cf.producedBy.localizedCaseInsensitiveContains("bundled") {
            source = .live(cf.producedBy.components(separatedBy: " · ").first ?? cf.producedBy)
        }
        start(app: app, reduceMotion: reduceMotion, live: false)
    }

    /// "Re-run analysis": the live model when a key is set, otherwise the bundled analysis again.
    func rerun(app: AppState, reduceMotion: Bool) {
        Haptics.soft()
        start(app: app, reduceMotion: reduceMotion, live: true)
    }

    /// Skip to the end (e.g. a tap on the thinking card).
    func finishNow(app: AppState) {
        guard phase != .done, !isAsking else { return }
        Haptics.tap()
        task?.cancel()
        withAnimation(Twin.Motion.spring) {
            typedWords = Int.max
            shownSuspects = app.dataset.caseFile?.suspects.count ?? 0
            phase = .done
        }
    }

    private func start(app: AppState, reduceMotion: Bool, live: Bool) {
        task?.cancel()
        task = Task { [weak self] in await self?.run(app: app, reduceMotion: reduceMotion, live: live) }
    }

    /// Sleeps; false when the reveal was cancelled (re-run tapped).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }

    private func run(app: AppState, reduceMotion: Bool, live: Bool) async {
        var apiKey = live ? InsightCredentials.apiKey() : nil
        #if DEBUG
        if live, apiKey == nil, let fake = DebugHooks.testKey { apiKey = fake }
        #endif
        let model = InsightCredentials.model()
        let dataset = app.dataset
        let days = apiKey != nil ? dataset.days.count
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
        if let apiKey {
            isAsking = true
            let outcome = await InsightService.analyze(dataset: dataset, apiKey: apiKey, model: model)
            isAsking = false
            guard !Task.isCancelled else { return }
            if outcome.isLive || app.dataset.caseFile?.producedBy.localizedCaseInsensitiveContains("bundled") != true {
                app.update { $0.caseFile = outcome.caseFile }
            }
            source = outcome.isLive ? .live(model) : outcome.source == .bundled(.offline) ? .bundled(.offline) : .bundled(.failed)
            if !outcome.isLive { Haptics.warning() }
        } else if live {
            // No key: replay the bundled analysis (and put it back if a live one was showing).
            if app.dataset.caseFile?.producedBy.localizedCaseInsensitiveContains("bundled") != true {
                app.update { $0.caseFile = InsightService.bundledCaseFile(for: $0) }
            }
            source = .bundled(.noKey)
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

        // 4. The rest of the case file.
        if !(await pause(0.35)) { return }
        withAnimation(Twin.Motion.spring) { phase = .done }
        #if DEBUG
        if !live, DebugHooks.autoRerun, await pause(1.5) { rerun(app: app, reduceMotion: reduceMotion) }
        #endif
    }
}

#if DEBUG
/// Launch arguments for checking paths that need a tap or a key, in Debug builds only:
///   -insightTestKey 1    re-run uses a deliberately invalid key (exercises the live call + fallback)
///   -insightAutoRerun 1  re-run once by itself after the first reveal
///   -insightRedFlags 1   add a red flag to the case file
enum DebugHooks {
    static var testKey: String? { UserDefaults.standard.bool(forKey: "insightTestKey") ? "invalid-test-key" : nil }
    static var autoRerun: Bool { UserDefaults.standard.bool(forKey: "insightAutoRerun") }
    @MainActor static func prepare(app: AppState) {
        if UserDefaults.standard.bool(forKey: "insightRedFlags"), app.dataset.caseFile?.redFlags.isEmpty == true {
            app.update { $0.caseFile?.redFlags = [
                "Your last note says the patches are weeping yellow fluid with honey-coloured crusts, and you feel feverish (38.4 °C). That can be an infection."
            ] }
        }
    }
}
#endif
