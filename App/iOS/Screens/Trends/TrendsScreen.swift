import SwiftUI
import EczemaKit

/// Trends — "what changed?" (STAGE-SPEC §3). Every number comes from `StageStory`.
///
/// Range picker (7 nights · 14 nights · All), this week's average with the week-over-week sticker,
/// the per-night chart (flare nights orange, dashed usual line, markers on two rows with dotted stems,
/// tap a night → cyan outline + detail strip), and "What changed" (tap a row → that night on the chart).
struct TrendsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range: TrendsRange = TodayTrendsLaunch.trendsRange ?? .twoWeeks
    /// The selected night (0 = oldest … 13 = last night).
    @State private var selected = StageStory.lastNightIndex
    /// Night dates are relative to now; moves on at midnight while the app stays open.
    @State private var now = Date()

    var body: some View {
        ScreenScaffold(title: "Trends", subtitle: range.subtitle) {
            UserAvatar()
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Twin.Space.m) {
                    section(0) {
                        ChartRangePicker(options: TrendsRange.allCases, selection: rangeBinding, title: \.title)
                    }
                    section(1) { mainCard(now) }
                        .id("trends-chart")
                    section(2) {
                        TrendsChangesCard(changes: TrendsStory.changes(now: now)) { change in
                            select(change.night)
                            withAnimation(Twin.Motion.slide) { proxy.scrollTo("trends-chart", anchor: .top) }
                        }
                    }
                    Color.clear.frame(height: 1).id("trends-bottom")
                }
                .onAppear { TodayTrendsLaunch.scrollForScreenshot(proxy, bottomID: "trends-bottom") }
            }
        }
        .onNewDay { now = Date() }
        .task {
            // `-trendsSelect 5` (debug): select a night after the entrance, as if it had been tapped.
            if let night = TodayTrendsLaunch.trendsSelect {
                try? await Task.sleep(for: .seconds(1.6))
                select(night)
            }
            if TodayTrendsLaunch.trendsTour { await tour() }
        }
    }

    /// `-trendsTour 1` (debug): select the new wash's night, the exams, zoom to 7 nights, back to 14,
    /// then last night again.
    private func tour() async {
        let steps: [(Double, () -> Void)] = [
            (2.2, { select(StageStory.bodyWashNight) }),
            (1.4, { select(TrendsStory.examsMarkerNight) }),
            (1.4, { withAnimation(Twin.Motion.spring) { setRange(.week) } }),
            (1.6, { withAnimation(Twin.Motion.spring) { setRange(.twoWeeks) } }),
            (1.4, { select(StageStory.lastNightIndex) }),
        ]
        for (wait, step) in steps {
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            step()
        }
    }

    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.05 + Double(i) * 0.1, distance: reduceMotion ? 0 : 16)
    }

    // MARK: Selection

    private var rangeBinding: Binding<TrendsRange> {
        Binding(get: { range }, set: { setRange($0) })
    }

    /// Changes the range; the selected night stays selected only while the new range shows it.
    private func setRange(_ new: TrendsRange) {
        range = new
        if !new.shows(selected) { selected = StageStory.lastNightIndex }
    }

    /// Selects night `i`, widening the range when it is not on the chart.
    private func select(_ i: Int) {
        guard StageStory.nights.indices.contains(i) else { return }
        withAnimation(Twin.Motion.spring) {
            if !range.shows(i) { range = .twoWeeks }
            selected = i
        }
    }

    // MARK: Main card

    private func mainCard(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Minutes scratching per night")
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                CountUp(value: StageStory.weekAverage.rounded(), font: Twin.Typeface.display, delay: 0.15, duration: 1.1)
                    .tracking(-2)
                Text("min / night this week")
                    .font(Twin.Typeface.callout)
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            .padding(.top, 6)
            TrendsWeekSticker(percent: StageStory.weekChangePercent)
                .padding(.top, 8)
            NightsChart(bars: TrendsStory.bars(now: now), firstVisible: TrendsStory.firstVisible(range),
                        usual: Double(StageStory.usual),
                        scaleTop: TrendsStory.scaleTop, markers: TrendsStory.markers,
                        selection: $selected, plotHeight: 170, markerBand: 64, delay: 0.25)
            legend
                .padding(.top, 10)
                .riseIn(1.0, distance: 0)
            TrendsNightDetail(night: TrendsStory.night(selected, now: now))
                .padding(.top, 12)
        }
        .twinCard()
    }

    /// "■ above usual   - - - your usual · 12 min"
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Twin.Palette.orange)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                    .frame(width: 10, height: 10)
                Text("above usual")
            }
            HStack(spacing: 5) {
                ChartHLine()
                    .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 18, height: 2)
                Text("your usual · \(StageStory.usual) min")
            }
        }
        .font(Twin.Typeface.mono(10))
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}
