import SwiftUI
import EczemaKit

/// Trends — "what changed?" (SPEC §4).
///
/// Range picker (7 days · 14 days · All), this week's average with the week-over-week sticker,
/// the per-day chart (flare colors, dashed usual line, markers where something started,
/// tap a day → cyan selection + detail strip), "What changed", and sleep & stress lines that
/// follow the selected day.
struct TrendsScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// nil = the default for the story (14 days; everything once a test runs).
    /// `-trendsRange week|twoWeeks|all` picks one at launch (screenshots).
    @State private var chosenRange: TrendsRange? = UserDefaults.standard.string(forKey: "trendsRange").flatMap(TrendsRange.init(rawValue:))
    @State private var chosenDay: Date?
    @State private var hasTapped = false

    var body: some View {
        let range = chosenRange ?? (app.dataset.experiment != nil ? .all : .twoWeeks)
        let snap = TrendsSnapshot(dataset: app.dataset, range: range)
        let selectedIndex = currentIndex(in: snap)
        ScreenScaffold(title: "Trends", subtitle: snap.subtitle) {
            UserAvatar()
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Twin.Space.m) {
                    if snap.days.isEmpty {
                        section(0) { TodayEmptyCard() }
                    } else {
                        section(0) {
                            ChartRangePicker(options: TrendsRange.allCases, selection: rangeBinding(range), title: \.title)
                        }
                        section(1) { mainCard(snap, selectedIndex: selectedIndex) }
                        if !snap.changes.isEmpty || !snap.routine.isEmpty {
                            section(2) {
                                TrendsChangesCard(changes: snap.changes, routine: snap.routine, days: snap.days) { change in
                                    select(change.startIndex, in: snap)
                                }
                            }
                        }
                        section(3) { TrendsBodyCard(snap: snap, selectedIndex: selectedIndex) }
                    }
                    Color.clear.frame(height: 1).id("trends-bottom")
                }
                .onAppear { TodayTrends.scrollForScreenshot(proxy, bottomID: "trends-bottom") }
            }
        }
        .task { await tour() }
    }

    /// `-trendsTour 1`: a scripted walk through the chart (screen recordings, stage backup):
    /// select the day the top suspect started, the first flare day, zoom to 7 days, back, today.
    private func tour() async {
        guard UserDefaults.standard.bool(forKey: "trendsTour") else { return }
        let snap = TrendsSnapshot(dataset: app.dataset, range: .all)
        guard !snap.days.isEmpty else { return }
        let firstChange = snap.changes.first?.startIndex ?? 0
        let firstFlare = snap.tones.firstIndex(of: .flare) ?? snap.days.count - 1
        let steps: [(Double, () -> Void)] = [
            (2.4, { select(firstChange, in: snap) }),
            (1.4, { select(firstFlare, in: snap) }),
            (1.6, { withAnimation(Twin.Motion.spring) { rangeBinding(chosenRange ?? .twoWeeks).wrappedValue = .week } }),
            (1.8, { withAnimation(Twin.Motion.spring) { chosenRange = nil } }),
            (1.4, { select(snap.days.count - 1, in: snap) }),
        ]
        for (wait, step) in steps {
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            step()
        }
    }

    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.04 + Double(i) * 0.08, distance: reduceMotion ? 0 : 16)
    }

    // MARK: Selection

    /// The selected day if it is visible, else the last day.
    private func currentIndex(in snap: TrendsSnapshot) -> Int? {
        guard !snap.days.isEmpty else { return nil }
        if let i = snap.index(of: chosenDay), snap.visibleRange.contains(i) { return i }
        return snap.days.count - 1
    }

    private func rangeBinding(_ current: TrendsRange) -> Binding<TrendsRange> {
        Binding(get: { current }, set: { new in
            chosenRange = new
            // Keep the selected day only while the new range still shows it.
            let snap = TrendsSnapshot(dataset: app.dataset, range: new)
            if let i = snap.index(of: chosenDay), !snap.visibleRange.contains(i) { chosenDay = nil }
        })
    }

    private func selectionBinding(_ snap: TrendsSnapshot, _ index: Int?) -> Binding<Date?> {
        Binding(get: { index.map { snap.days[$0].day } },
                set: { new in
                    chosenDay = new
                    if !hasTapped { withAnimation(Twin.Motion.spring) { hasTapped = true } }
                })
    }

    /// Selects day `i`, widening the range when it is not visible.
    private func select(_ i: Int, in snap: TrendsSnapshot) {
        guard snap.days.indices.contains(i) else { return }
        withAnimation(Twin.Motion.spring) {
            if !snap.visibleRange.contains(i) { chosenRange = snap.rangeShowing(i) }
            chosenDay = snap.days[i].day
            hasTapped = true
        }
    }

    // MARK: Main card

    private func mainCard(_ snap: TrendsSnapshot, selectedIndex: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Minutes scratching per day")
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                CountUp(value: snap.thisWeek.rounded(), font: Twin.Typeface.display, delay: 0.12, duration: 1.1)
                    .tracking(-2)
                Text("min / day this week")
                    .font(Twin.Typeface.sans(15))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            .padding(.top, 4)
            TrendsWeekSticker(change: snap.weekChange)
                .padding(.top, 8)
            DailyScratchChart(bars: snap.bars(), usual: snap.usual, markers: snap.markers,
                              selection: selectionBinding(snap, selectedIndex), plotHeight: 150, delay: 0.25)
                .padding(.top, 20)
            if let i = selectedIndex {
                TrendsDayDetail(snap: snap, index: i, showHint: !hasTapped)
                    .padding(.top, 14)
            }
        }
        .twinCard()
    }
}

/// "▲ up 158% from last week" (orange) · "▼ down 20% from last week" (lime) · "About the same as last week".
struct TrendsWeekSticker: View {
    let change: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        Group {
            if let change {
                let pct = Int((abs(change) * 100).rounded())
                if change >= 0.1 {
                    Sticker(text: "up \(pct)% from last week", icon: "arrowtriangle.up.fill", fill: Twin.Palette.orange)
                } else if change <= -0.1 {
                    Sticker(text: "down \(pct)% from last week", icon: "arrowtriangle.down.fill", fill: Twin.Palette.lime)
                } else {
                    Sticker(text: "About the same as last week", icon: "equal", fill: Twin.Palette.paper)
                }
            } else {
                Sticker(text: "Your first week", icon: "sparkles", fill: Twin.Palette.paper)
            }
        }
        .scaleEffect(stamped || reduceMotion ? 1 : 0.55, anchor: .leading)
        .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -8), anchor: .leading)
        .opacity(stamped ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(0.6) : Twin.Motion.bouncy.delay(0.6)) { stamped = true }
        }
    }
}
