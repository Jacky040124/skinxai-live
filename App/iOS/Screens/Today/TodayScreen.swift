import SwiftUI
import EczemaKit

/// Today — last night at a glance (STAGE-SPEC §3). Every number comes from `StageStory`.
///
/// The last-night card (ring, "× your usual", the worst hours, the night in quarter hours), the pink
/// "Ask Claude what changed" card that opens Insight, Sleep and Stress, and "Around you". The top bar
/// has the live pill (only while the watch tracks sleep) next to the avatar.
///
/// Sections rise in one after another, numbers count up, the ring fills, the bars grow. When the watch
/// stops tracking (he woke up), the sections play their entrance again once Today is back on screen:
/// last night is ready.
struct TodayScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped to play the entrance again.
    @State private var entrance = 0
    /// Today is on screen (not covered by the live monitor, not on another tab).
    @State private var onScreen = false
    /// The watch's last tracking state; nil until the first value arrives.
    @State private var wasTracking: Bool?
    /// The watch stopped while the live monitor covered Today: replay when Today is back.
    @State private var replayWhenBack = false
    /// The date in the top bar; moves on at midnight while the app stays open.
    @State private var now = Date()

    var body: some View {
        ScreenScaffold(title: "Today", subtitle: TodayStory.topBarDate(now)) {
            HStack(spacing: 10) {
                LivePill()
                UserAvatar()
            }
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("today-top")
                    sections
                        .id(entrance)
                    Color.clear.frame(height: 1).id("today-bottom")
                }
                .onAppear {
                    onScreen = true
                    TodayTrendsLaunch.scrollForScreenshot(proxy, bottomID: "today-bottom")
                    if replayWhenBack {
                        replayWhenBack = false
                        replay(proxy, after: 0.45)
                    }
                }
                .onDisappear { onScreen = false }
                .onNewDay { now = Date() }
                .onReceive(LiveSession.shared.$tracking.removeDuplicates()) { tracking in
                    defer { wasTracking = tracking }
                    guard wasTracking == true, !tracking else { return }
                    // He woke up: last night is ready.
                    if onScreen { replay(proxy, after: 0.9) } else { replayWhenBack = true }
                }
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Twin.Space.m) {
            section(0) { TodayNightCard() }
            section(1) {
                // Leads to Insight; it never says what changed (Claude finds out there).
                TodayActionCard(glyph: "✶", title: TodayStory.ctaTitle, subtitle: "Ask Claude what changed") {
                    app.select(.insight)
                } accessory: { EmptyView() }
                .accessibilityHint("Opens Insight")
            }
            section(2) {
                HStack(alignment: .top, spacing: Twin.Space.m) {
                    sleepCard
                    stressCard
                }
                .fixedSize(horizontal: false, vertical: true)   // both cards as tall as the taller one
            }
            section(3) { TodayAroundYouCard() }
        }
    }

    /// Entrance choreography: each section rises in after the previous one (fade only with Reduce Motion).
    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.05 + Double(i) * 0.1, distance: reduceMotion ? 0 : 16)
    }

    private var sleepCard: some View {
        let last = StageStory.LastNight.sleepHours
        let usual = TodayStory.usualSleep
        return TodayMiniCard(title: "Sleep", value: last, decimals: 1, unit: "h",
                             note: "woke up \(StageStory.LastNight.wakeUps)×",
                             worse: last < usual - 0.5, delay: 0.35)
    }

    private var stressCard: some View {
        let hrv = Double(StageStory.LastNight.hrvMs)
        let usual = Double(StageStory.usualHrvMs)
        let note = hrv < usual * 0.9 ? "lower than usual" : (hrv > usual * 1.1 ? "higher than usual" : "about usual")
        return TodayMiniCard(title: "Stress (HRV)", value: hrv, decimals: 0, unit: "ms", note: note,
                             worse: hrv < usual * 0.9, delay: 0.42)
    }

    /// Plays the entrance again (from the top) after `delay`, once the monitor is gone and the phone is upright.
    private func replay(_ proxy: ScrollViewProxy, after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            proxy.scrollTo("today-top", anchor: .top)
            entrance += 1
        }
    }
}
