import SwiftUI
import EczemaKit

/// Trends — see what lines up across time, in one picture. Every number comes from `StageStory` and
/// its longer history `StageHistory` (74 nights).
///
/// - Range picker (7 nights · All time) and one computed reading line ("Two flares: …").
/// - One stacked timeline: scratching per night (bars), sleep, humidity, temperature and stress (HRV)
///   as thin tracks, and the events (new products in use, exams, late gym) on lanes under them, all on
///   the same night axis and scrolling together. Tap a night → a cyan band across every track and the
///   night's detail strip. Tap an event → its sheet (item, dates, ingredients, with-vs-without, verdict,
///   "Ask Claude about this").
/// - "More charts" (collapsed): the calendar, trigger impact, last night's sleep and weekday cards.
struct TrendsScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// All time by default: the calm weeks make the flares stand out.
    @State private var range: TrendsRange = TodayTrendsLaunch.trendsRange ?? .all
    /// The selected night (0 = oldest of the story's 14 … 13 = last night; earlier nights negative).
    @State private var selected = StageStory.lastNightIndex
    /// A night the scrolling chart moves to the right edge (debug `-trendsScrollBack`).
    @State private var focus: Int?
    /// The event whose sheet is open.
    @State private var openEvent: TrendsEvent?
    @State private var more = TrendsLaunch.more
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
                    section(1) { timelineCard(now) }
                        .id("trends-chart")
                    section(2) { TrendsMoreHeader(open: $more) }
                        .id("trends-more")
                    if more {
                        Group {
                            TrendsCalendarCard().id("trends-calendar")
                            TrendsTriggersCard { app.select(.insight) }.id("trends-triggers")
                            TrendsSleepCard().id("trends-sleep")
                            TrendsWeekdayCard().id("trends-weekday")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Color.clear.frame(height: 1).id("trends-bottom")
                }
                .onAppear { TodayTrendsLaunch.scrollForScreenshot(proxy, bottomID: "trends-bottom") }
            }
        }
        .onNewDay { now = Date() }
        .sheet(item: $openEvent) { event in
            TrendsEventSheet(detail: TrendsEventDetail(event, now: now)) {
                app.select(.insight)
            }
        }
        .task {
            // `-trendsSelect 5` (debug): select a night after the entrance, as if it had been tapped.
            if let night = TrendsLaunch.select {
                try? await Task.sleep(for: .seconds(1.6))
                select(night)
            }
            // `-trendsScrollBack 9` (debug): scroll the long chart back 9 nights.
            if let back = TrendsLaunch.scrollBack {
                try? await Task.sleep(for: .seconds(1.8))
                focus = StageStory.lastNightIndex - back
            }
            // `-trendsEvent bodywash` (debug): open an event's sheet.
            if let id = TrendsLaunch.event, let event = TrendsEvent.find(id) {
                try? await Task.sleep(for: .seconds(1.2))
                openEvent = event
            }
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
        guard TrendsStory.nightIDs.contains(i) else { return }
        withAnimation(Twin.Motion.spring) {
            if !range.shows(i) { range = .all }
            selected = i
        }
    }

    // MARK: Timeline card

    private func timelineCard(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            reading(now)
            TimelineChart(nights: TrendsStory.nights(range, now: now), tracks: TrendsStory.tracks,
                          lanes: TrendsStory.lanes(range), events: TrendsStory.events(range),
                          usual: Double(StageStory.usual), scaleTop: TrendsStory.scaleTop,
                          selection: $selected, focus: focus, window: 21, delay: 0.25) { id in
                Haptics.tap()
                openEvent = TrendsEvent.find(id)
            }
            .id(range)
            .transition(.opacity)
            .padding(.top, 14)
            TrendsLegend()
                .padding(.top, 10)
                .riseIn(0.9, distance: 0)
            TrendsNightDetail(night: TrendsStory.detail(selected, now: now)) { event in
                openEvent = event
            }
            .padding(.top, 12)
        }
        .twinCard()
    }

    /// "Two flares: Oct 6–9 after the new sweater and detergent sample, and Oct 20–now after the new
    /// body wash. Weather, exams and sleep didn't line up."
    private func reading(_ now: Date) -> some View {
        let t = TrendsStory.reading(range, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            (Text(t.lead + " ").font(Twin.Typeface.sans(16, .bold)).foregroundColor(Twin.Palette.ink)
                + Text(t.rest).font(Twin.Typeface.sans(16)).foregroundColor(Twin.Palette.ink))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !t.ruledOut.isEmpty {
                Text(t.ruledOut)
                    .font(Twin.Typeface.sans(14))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(t.lead + t.rest)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.25), value: range)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
