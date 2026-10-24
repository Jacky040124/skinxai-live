import SwiftUI
import EczemaKit

/// Insight — Claude's case file. The hero of the demo: thinking → the summary types out → suspects fly in
/// by rank (the #1 with an evidence timeline that draws itself) → what can't be separated yet → a pink
/// "start a test" action. Plays once per launch (and again for the demo tour); fades only with Reduce Motion.
struct InsightScreen: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var tour: DemoTour
    @EnvironmentObject var data: DataModeController
    @EnvironmentObject var toasts: ShellToasts
    @ObservedObject private var session = InsightSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True when the reveal already ran before this visit: use the regular entrance choreography instead.
    @State private var revisit = InsightSession.shared.phase == .done

    var body: some View {
        let caseFile = app.dataset.caseFile
        ScreenScaffold(title: "Insight", subtitle: subtitle(caseFile)) {
            ClaudeBadge(active: session.phase == .thinking || session.isAsking)
        } content: {
            if let caseFile {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: Twin.Space.m) {
                        caseContent(caseFile)
                        Color.clear.frame(height: 1).id(ScrollHook.bottomID)
                    }
                    .onChange(of: session.phase) { _, phase in
                        // A replay or re-run plays the full reveal: no extra entrance on top of it.
                        if phase == .thinking { revisit = false }
                        if phase == .done { revealDone(proxy) }
                    }
                    .onAppear { if session.phase == .done { ScrollHook.scrollIfAsked(proxy) } }
                }
            } else if session.isAsking {
                // "Analyze what I have" with nothing on file yet: the same thinking card as a re-run.
                ThinkingCard(session: session, bundledAllowed: false) { session.stopWaiting(app: app) }
                    .transition(.opacity)
            } else {
                NoCaseFileCard(state: noCaseFileState, stats: TrackedSoFar(dataset: app.dataset),
                               isDemo: app.dataset.isDemo) {
                    session.rerun(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
                } openSettings: {
                    app.showSettings = true
                }
                .entranceRise(0.05)
            }
        }
        .onAppear(perform: appear)
        .onChange(of: app.showSettings) { _, open in if !open { session.refreshKeyState() } }
        .onChange(of: session.miss) { _, miss in
            // A re-run with no key over a live case file: nothing to replay, so say what would help.
            if miss == .needsKey, app.dataset.caseFile != nil {
                toasts.show("Add your OpenRouter key in Settings to re-run", mood: .info, symbol: "key.fill", seconds: 2.6)
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: session.shownSuspects) { old, new in new > old }
        #if DEBUG
        .onChange(of: session.isSlow) { _, slow in
            if slow, DebugHooks.script == "stopWaiting" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { session.stopWaiting(app: app) }
            }
        }
        #endif
    }

    /// The bundled analysis is Douglas's: it only stands in on his story's day 14 or during the test.
    private var bundledAllowed: Bool {
        app.dataset.isDemo && (app.experimentDay != nil || data.storyDay >= StoryPoint.flareLength)
    }

    private var noCaseFileState: NoCaseFileCard.State {
        switch session.miss {
        case .needsKey: .needsKey
        case .fellBack(.offline): .offline
        case .fellBack(.slow): .slow
        case .fellBack: .failed
        case .stopped, nil: .ready
        }
    }

    private func appear() {
        // The demo tour always shows the whole reveal, even when it already played this launch.
        if tour.isRunning, session.phase != .idle {
            session.replay(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
        } else {
            session.appear(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
        }
    }

    /// The reveal finished (the #1 timeline has landed its "+2 DAYS"). In the demo tour the next touch is
    /// "Start test": glide down so the "can't separate yet" note and the pink button are on camera before the
    /// finger arrives.
    private func revealDone(_ proxy: ScrollViewProxy) {
        ScrollHook.scrollIfAsked(proxy)
        if tour.isRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard tour.isRunning else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .smooth(duration: 0.85)) {
                    proxy.scrollTo(StartTestButton.scrollID, anchor: UnitPoint(x: 0.5, y: 0.6))
                }
            }
        }
        #if DEBUG
        if DebugHooks.script == "startTest", app.dataset.experiment == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(Twin.Motion.spring) { proxy.scrollTo(StartTestButton.scrollID, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if app.dataset.experiment == nil, app.tab == .insight { StoryTravel.startExperiment(app: app) }
                }
            }
        }
        #endif
    }

    private func subtitle(_ caseFile: CaseFile?) -> String {
        guard let caseFile else { return "No case file yet" }
        return "Case #\(caseFile.number) · \(caseFile.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    @ViewBuilder
    private func caseContent(_ caseFile: CaseFile) -> some View {
        let window = windowDays(caseFile)
        let suspects = Array(caseFile.suspects.prefix(3))

        CaseSummaryCard(caseFile: caseFile, session: session, bundledAllowed: bundledAllowed) {
            session.finishNow(app: app)
        }
        .entranceRise(0.04, enabled: revisit)

        ForEach(Array(suspects.prefix(session.shownSuspects).enumerated()), id: \.element.id) { index, suspect in
            SuspectCard(rank: index + 1, suspect: suspect, window: index == 0 ? window : nil, instant: reduceMotion)
                .transition(reduceMotion ? .opacity : .flyIn)
                .entranceRise(Double(index + 1) * Twin.Motion.stagger + 0.04, enabled: revisit)
        }

        if session.phase == .done {
            Group {
                ForEach(Array(caseFile.cannotSeparate.enumerated()), id: \.offset) { _, note in
                    CannotSeparateNote(text: note)
                }
                if !caseFile.redFlags.isEmpty {
                    RedFlagsCard(flags: caseFile.redFlags)
                }
                if let plan = StoryTravel.plan(for: caseFile, in: app.dataset) {
                    StartTestButton(plan: plan, experiment: app.dataset.experiment,
                                    day: app.dataset.experimentDays().count, quiet: !caseFile.redFlags.isEmpty)
                        .tourTarget("startTest")
                        .id(StartTestButton.scrollID)
                        .padding(.top, 4)
                }
                Text("Not a diagnosis. If skin oozes, crusts or you get a fever, see a doctor today.")
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                InsightActions(note: sourceNote(caseFile), asking: session.isAsking) {
                    session.rerun(app: app, reduceMotion: reduceMotion, bundledAllowed: bundledAllowed)
                } share: {
                    app.showReport = true
                }
            }
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 16)))
            .entranceRise(Double(suspects.count + 1) * Twin.Motion.stagger + 0.04, enabled: revisit)
        }
    }

    /// Small print: where the case file on screen came from (read from the case file itself), plus what
    /// happened to the last re-run when it didn't bring a new live answer.
    private func sourceNote(_ caseFile: CaseFile) -> String {
        if caseFile.isBundled {
            switch session.miss {
            case .fellBack(let reason): return reason.note
            case .stopped: return "Bundled analysis · live call stopped"
            case .needsKey, nil: return InsightOutcome.BundledReason.noKey.note
            }
        }
        let live = "Live analysis · \(caseFile.liveModel ?? "Claude")"
        switch session.miss {
        case .fellBack(.offline): return live + " · re-run offline"
        case .fellBack(.slow): return live + " · re-run timed out"
        case .fellBack: return live + " · re-run failed"
        case .stopped: return live + " · re-run stopped"
        case .needsKey: return live + " · add a key to re-run"
        case nil: return live
        }
    }

    private func windowDays(_ caseFile: CaseFile) -> EvidenceWindow {
        let cal = Calendar.current
        let start = cal.startOfDay(for: caseFile.windowStart), end = cal.startOfDay(for: caseFile.windowEnd)
        var days = app.dataset.days.filter { $0.day >= start && $0.day <= end }
        if days.count < 3 { days = Array(app.dataset.days.suffix(14)) }
        let minutes = days.map(\.scratchMinutes)
        let threshold = StatsEngine.threshold(baseline: StatsEngine.baseline(minutes))
        return EvidenceWindow(days: days.map(\.day), minutes: minutes, threshold: threshold)
    }
}

// MARK: - Screenshot hook

/// `-scrollTo bottom` (launch argument, Debug builds) scrolls a screen to its end once it has settled, so
/// scripts/shot can capture the lower half. No effect otherwise.
enum ScrollHook {
    static let bottomID = "screen-bottom"
    static var wanted: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "scrollTo") == "bottom"
        #else
        false
        #endif
    }
    static func scrollIfAsked(_ proxy: ScrollViewProxy, after delay: Double = 0.8) {
        guard wanted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Leave room for the tab bar that floats over the bottom of the scroll view.
            withAnimation(Twin.Motion.spring) { proxy.scrollTo(bottomID, anchor: UnitPoint(x: 0.5, y: 0.86)) }
        }
    }
}

// MARK: - Entrance

/// Rises 14 pt and fades in after `delay` the first time it appears (fade only with Reduce Motion).
/// With `enabled == false` the content simply shows. Identity-stable: `enabled` can change later without
/// rebuilding the content, and views inserted after that just show (their own transition plays instead).
struct EntranceRise: ViewModifier {
    var delay: Double
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(delay: Double, enabled: Bool) {
        self.delay = delay
        self.enabled = enabled
        _shown = State(initialValue: !enabled)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(Twin.Motion.spring.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func entranceRise(_ delay: Double, enabled: Bool = true) -> some View {
        modifier(EntranceRise(delay: delay, enabled: enabled))
    }
}

// MARK: - Fly-in (suspect cards)

private struct FlyIn: ViewModifier {
    var progress: Double     // 0 = off, 1 = in place
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .rotationEffect(.degrees(-2.5 * (1 - progress)), anchor: .topLeading)
            .offset(y: 44 * (1 - progress))
    }
}

extension AnyTransition {
    static var flyIn: AnyTransition {
        .asymmetric(insertion: .modifier(active: FlyIn(progress: 0), identity: FlyIn(progress: 1)),
                    removal: .opacity.animation(.easeOut(duration: 0.15)))
    }

    /// Content swapped in place: the old one leaves quickly, the new one comes a beat later, so two layers
    /// of text never show at once.
    static var swapInPlace: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)).animation(Twin.Motion.spring.delay(0.14)),
                    removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
}

// MARK: - "✶ Claude" badge

struct ClaudeBadge: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, isActive: active)
                // The turn is movement: Reduce Motion keeps only the opacity pulse.
                .rotationEffect(.degrees(active && !reduceMotion ? 90 : 0))
                .animation(active && !reduceMotion ? .linear(duration: 1.6).repeatForever(autoreverses: false) : .spring(),
                           value: active)
            Text("Claude").font(Twin.Typeface.sans(13, .bold))
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .sticker(Twin.Palette.pink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(active ? "Claude is thinking" : "Analysis by Claude")
    }
}
