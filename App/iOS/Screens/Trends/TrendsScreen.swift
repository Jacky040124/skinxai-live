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
    /// Health permission state (shell): real data offers "Allow Health" when nothing came in.
    @EnvironmentObject var access: DeviceAccess
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
                            .id("trends-chart")
                        if !snap.changes.isEmpty || !snap.routine.isEmpty {
                            section(2) {
                                TrendsChangesCard(changes: snap.changes, routine: snap.routine, days: snap.days) { change in
                                    // Show that day on the chart, and bring the chart into view.
                                    select(change.startIndex, in: snap)
                                    withAnimation(Twin.Motion.slide) { proxy.scrollTo("trends-chart", anchor: .top) }
                                }
                            }
                        }
                        section(3) {
                            TrendsBodyCard(snap: snap, selectedIndex: selectedIndex,
                                           canAskHealth: access.health == .notAsked || access.health == .off,
                                           onConnect: access.health == .unavailable ? nil : { app.showPermissions = true })
                        }
                    }
                    Color.clear.frame(height: 1).id("trends-bottom")
                }
                .onAppear { TodayTrends.scrollForScreenshot(proxy, bottomID: "trends-bottom") }
            }
        }
        .task {
            #if DEBUG
            TodayTrendsFixture.applyIfRequested(app)
            #endif
            await tour()
        }
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
            (1.6, { withAnimation(Twin.Motion.spring) { setRange(.week) } }),
            (1.8, { withAnimation(Twin.Motion.spring) { setRange(nil) } }),
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
        Binding(get: { current }, set: { setRange($0) })
    }

    /// Changes the range; the selected day stays selected only while the new range shows it.
    private func setRange(_ new: TrendsRange?) {
        chosenRange = new
        let snap = TrendsSnapshot(dataset: app.dataset, range: new ?? (app.dataset.experiment != nil ? .all : .twoWeeks))
        if let i = snap.index(of: chosenDay), !snap.visibleRange.contains(i) { chosenDay = nil }
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
                if let week = snap.thisWeek {
                    CountUp(value: week.rounded(), font: Twin.Typeface.display, delay: 0.12, duration: 1.1)
                        .tracking(-2)
                } else {
                    // Real data, nothing tracked this week: no number rather than a false "0".
                    Text(TodayTrends.Format.noValue)
                        .font(Twin.Typeface.sans(56, .regular)).tracking(1)
                        .foregroundStyle(Twin.Palette.inkHint)
                }
                Text("min / day this week")
                    .font(Twin.Typeface.sans(15))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            .padding(.top, 4)
            TrendsWeekSticker(change: snap.weekChange, tracking: snap.thisWeek != nil)
                .padding(.top, 8)
            DailyScratchChart(bars: snap.bars(), usual: snap.usual, usualLabel: snap.usualLabel, markers: snap.markers,
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

/// "▲ up 158% from last week" (orange) · "▼ down 20% from last week" (lime) · "About the same as
/// last week". Stamps in like Today's "× your usual" sticker, then the percent counts up from 0
/// (and rolls to the new value when the data changes).
struct TrendsWeekSticker: View {
    let change: Double?
    /// false = the watch tracked nothing this week (real data).
    var tracking = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    @State private var shownPct: Double = 0

    private static let stampDelay = 0.6

    private enum Kind: Equatable { case up(Int), down(Int), same, first, none }

    private var kind: Kind {
        guard tracking else { return .none }
        guard let change else { return .first }
        let pct = Int((abs(change) * 100).rounded())
        if change >= 0.1 { return .up(pct) }
        if change <= -0.1 { return .down(pct) }
        return .same
    }

    private var pct: Int {
        switch kind { case .up(let p), .down(let p): p; default: 0 }
    }

    var body: some View {
        sticker
            .scaleEffect(stamped || reduceMotion ? 1 : 0.55, anchor: .leading)
            .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -8), anchor: .leading)
            .opacity(stamped ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(Self.stampDelay)
                                           : Twin.Motion.bouncy.delay(Self.stampDelay)) { stamped = true }
                withAnimation(.easeOut(duration: 0.9).delay(Self.stampDelay + 0.05)) { shownPct = Double(pct) }
            }
            .onChange(of: pct) { _, new in withAnimation(.easeOut(duration: 0.9)) { shownPct = Double(new) } }
    }

    @ViewBuilder private var sticker: some View {
        switch kind {
        case .up(let p):
            counting(icon: "arrowtriangle.up.fill", lead: "up ", pct: p, fill: Twin.Palette.orange)
        case .down(let p):
            counting(icon: "arrowtriangle.down.fill", lead: "down ", pct: p, fill: Twin.Palette.lime)
        case .same:
            Sticker(text: "About the same as last week", icon: "equal", fill: Twin.Palette.paper)
        case .first:
            Sticker(text: "Your first week", icon: "sparkles", fill: Twin.Palette.paper)
        case .none:
            Sticker(text: "No episodes this week", icon: "applewatch", fill: Twin.Palette.paper)
        }
    }

    /// Same metrics as `Sticker`, with the percent as a counting number.
    private func counting(icon: String, lead: String, pct: Int, fill: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            HStack(spacing: 0) {
                Text(lead)
                CountingText(value: shownPct, decimals: 0, font: Twin.Typeface.sans(12, .bold))
                Text("% from last week")
            }
            .font(Twin.Typeface.sans(12, .bold))
            .lineLimit(1)
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sticker(fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lead)\(pct)% from last week")
    }
}
