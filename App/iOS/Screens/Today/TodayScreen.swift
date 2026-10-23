import SwiftUI
import EczemaKit

/// Today — "how bad is it right now?" (SPEC §4).
///
/// Hero ring card (tap → today's episodes), the Claude call-to-action (or the running test),
/// Sleep and Stress mini cards, "Around you · auto", and what the user logged today.
/// Sections rise in one after another; every number counts up; the ring fills; bars grow.
struct TodayScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEpisodes = false

    var body: some View {
        let now = Date()
        let snap = TodaySnapshot(dataset: app.dataset, now: now)
        ScreenScaffold(title: "Today", subtitle: TodayTrends.Format.weekdayDay(now)) {
            UserAvatar()
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Twin.Space.m) {
                    sections(snap)
                    Color.clear.frame(height: 1).id("today-bottom")
                }
                .onAppear { TodayTrends.scrollForScreenshot(proxy, bottomID: "today-bottom") }
            }
        }
        .sheet(isPresented: $showEpisodes) {
            if let snap { TodayEpisodesSheet(snap: snap) }
        }
        .task {
            // `-screen episodes` opens Today with today's episodes sheet (screenshots, demo).
            guard UserDefaults.standard.string(forKey: "screen") == "episodes", snap != nil else { return }
            try? await Task.sleep(for: .seconds(0.9))
            showEpisodes = true
        }
    }

    @ViewBuilder private func sections(_ snap: TodaySnapshot?) -> some View {
        if let snap {
            section(0) {
                Button { showEpisodes = true } label: { TodayHeroCard(snap: snap) }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Shows today's episodes")
            }
            // The demo tour (`-autoplay tour`) shows its touch ripple on this card.
            section(1) { claudeCard(snap).tourTarget("claudeCard") }
            section(2) {
                HStack(alignment: .top, spacing: Twin.Space.m) {
                    sleepCard(snap)
                    stressCard(snap)
                }
            }
            section(3) { TodayAroundYouCard(day: snap.day, auto: snap.autoToday) }
            section(4) {
                TodayLoggedCard(exposures: snap.loggedToday) { app.showTagSheet = true }
            }
        } else {
            section(0) { TodayEmptyCard() }
        }
    }

    /// Entrance choreography: each section rises in after the previous one (fade only with Reduce Motion).
    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.04 + Double(i) * 0.08, distance: reduceMotion ? 0 : 16)
    }

    // MARK: Claude / test call-to-action

    @ViewBuilder private func claudeCard(_ snap: TodaySnapshot) -> some View {
        let ds = snap.dataset
        if let test = ds.experiment, test.status != .stopped {
            let dayN = min(max(ds.experimentDays().count, 1), test.plan.lengthDays)
            let left = test.plan.lengthDays - dayN
            switch test.status {
            case .running:
                TodayActionCard(symbol: "flask.fill",
                                title: "Day \(dayN) of your test",
                                subtitle: "\(test.plan.title) · " + (left == 0 ? "last day" : TodayTrends.Format.count(left, "day") + " to go"),
                                action: { app.select(.experiment) }) {
                    TodayTestTiles(day: dayN, length: test.plan.lengthDays)
                }
            case .confirmed:
                TodayActionCard(symbol: "checkmark.seal.fill", title: "Your test result is in",
                                subtitle: "It worked: scratching dropped while you kept the change.",
                                fill: Twin.Palette.limeSoft, tile: Twin.Palette.lime,
                                action: { app.select(.experiment) }) { EmptyView() }
            default:
                TodayActionCard(symbol: "flask.fill", title: "Your test result is in",
                                subtitle: "No clear change yet. See what Claude suggests next.",
                                action: { app.select(.experiment) }) { EmptyView() }
            }
        } else if let cf = ds.caseFile {
            if let flag = cf.redFlags.first {
                TodayActionCard(symbol: "exclamationmark.triangle.fill", title: "Please see a doctor today",
                                subtitle: flag, fill: Twin.Palette.redSoft, tile: Twin.Palette.red, shimmer: false,
                                action: { app.select(.insight) }) { EmptyView() }
            } else if cf.patternFound, let top = cf.suspects.first {
                TodayActionCard(glyph: "✶", title: "Claude found a likely trigger",
                                subtitle: Self.jumpLine(top),
                                action: { app.select(.insight) }) { EmptyView() }
            } else {
                TodayActionCard(glyph: "✶", title: "Claude's case file is ready",
                                subtitle: "No clear trigger yet. See what to watch next.",
                                action: { app.select(.insight) }) { EmptyView() }
            }
        } else {
            TodayActionCard(glyph: "✶", title: "Claude is learning your pattern",
                            subtitle: "Your first case file comes after a few nights.",
                            fill: Twin.Palette.cream, tile: Twin.Palette.paper, shimmer: false,
                            action: { app.select(.insight) }) { EmptyView() }
        }
    }

    /// "Your scratching jumped 2 days after a change."
    static func jumpLine(_ s: Suspect, calendar: Calendar = .current) -> String {
        guard let a = s.startedOn, let b = s.flareOn,
              let lag = calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day,
              lag >= 0 else { return "See what changed before your scratching jumped." }
        if lag == 0 { return "Your scratching jumped the same day as a change." }
        return "Your scratching jumped \(TodayTrends.Format.count(lag, "day")) after a change."
    }

    // MARK: Mini cards

    private func sleepCard(_ snap: TodaySnapshot) -> some View {
        let hours = snap.day.sleepHours
        return TodayMetricCard(title: "Sleep", value: hours, decimals: 1, unit: "h",
                               note: "woke up \(snap.day.wakeUps)×",
                               worse: snap.usualSleep.map { hours < $0 - 0.5 },
                               history: snap.recent(7, \.sleepHours), usual: snap.usualSleep, delay: 0.3)
    }

    private func stressCard(_ snap: TodaySnapshot) -> some View {
        let hrv = snap.day.hrvMs
        let usual = snap.usualHRV
        let note: String = usual.map { u in
            hrv < u * 0.9 ? "lower than usual" : (hrv > u * 1.1 ? "higher than usual" : "about usual")
        } ?? "heart rate variability"
        return TodayMetricCard(title: "Stress (HRV)", value: hrv, decimals: 0, unit: "ms",
                               note: note, worse: usual.map { hrv < $0 * 0.9 },
                               history: snap.recent(7, \.hrvMs), usual: usual, delay: 0.38)
    }
}
