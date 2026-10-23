import SwiftUI
import EczemaKit

/// Insight — Claude's case file. The hero of the demo: thinking → the summary types out → suspects fly in
/// by rank (the #1 with an evidence timeline that draws itself) → what can't be separated yet → a pink
/// "start a test" action. Plays once per launch; instant final state with Reduce Motion.
struct InsightScreen: View {
    @EnvironmentObject var app: AppState
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
                        if phase == .done { ScrollHook.scrollIfAsked(proxy) }
                    }
                    .onAppear { if session.phase == .done { ScrollHook.scrollIfAsked(proxy) } }
                }
            } else {
                NoCaseFileCard(asking: session.isAsking) { session.rerun(app: app, reduceMotion: reduceMotion) }
                    .riseIn(0.05)
            }
        }
        .onAppear { session.appear(app: app, reduceMotion: reduceMotion) }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: session.shownSuspects) { old, new in new > old }
    }

    private func subtitle(_ caseFile: CaseFile?) -> String {
        guard let caseFile else { return "No case file yet" }
        return "Case #\(caseFile.number) · \(caseFile.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    @ViewBuilder
    private func caseContent(_ caseFile: CaseFile) -> some View {
        let window = windowDays(caseFile)
        let suspects = Array(caseFile.suspects.prefix(3))

        CaseSummaryCard(caseFile: caseFile, session: session)
            .entrance(0, revisit)
            .onTapGesture { session.finishNow(app: app) }

        ForEach(Array(suspects.prefix(session.shownSuspects).enumerated()), id: \.element.id) { index, suspect in
            SuspectCard(rank: index + 1, suspect: suspect, window: index == 0 ? window : nil, instant: reduceMotion)
                .transition(reduceMotion ? .opacity : .flyIn)
                .entrance(index + 1, revisit)
        }

        if session.phase == .done {
            Group {
                ForEach(Array(caseFile.cannotSeparate.enumerated()), id: \.offset) { _, note in
                    CannotSeparateNote(text: note)
                }
                if !caseFile.redFlags.isEmpty {
                    RedFlagsCard(flags: caseFile.redFlags)
                }
                if let plan = caseFile.nextExperiment {
                    StartTestButton(plan: plan, experiment: app.dataset.experiment,
                                    day: app.dataset.experimentDays().count, quiet: !caseFile.redFlags.isEmpty)
                        .padding(.top, 4)
                }
                Text("Not a diagnosis. If skin oozes, crusts or you get a fever, see a doctor today.")
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                InsightActions(source: session.source, asking: session.isAsking) {
                    session.rerun(app: app, reduceMotion: reduceMotion)
                } share: {
                    app.showReport = true
                }
            }
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 16)))
            .entrance(suspects.count + 1, revisit)
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

// MARK: - Entrance on later visits

private struct Entrance: ViewModifier {
    var index: Int
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.riseIn(Double(index) * Twin.Motion.stagger + 0.04) } else { content }
    }
}

private extension View {
    func entrance(_ index: Int, _ enabled: Bool) -> some View { modifier(Entrance(index: index, enabled: enabled)) }
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
}

// MARK: - "✶ Claude" badge

struct ClaudeBadge: View {
    var active: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, isActive: active)
                .rotationEffect(.degrees(active ? 90 : 0))
                .animation(active ? .linear(duration: 1.6).repeatForever(autoreverses: false) : .spring(), value: active)
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
