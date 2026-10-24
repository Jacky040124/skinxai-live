import SwiftUI
import EczemaKit

// The pattern cards under "What changed": each one is an eyebrow, one plain-English takeaway that
// says what the data shows (linked or not), and the chart. All numbers come from `StageHistory`
// (74 nights: 60 calm ones before `StageStory`'s 14).

// MARK: - Card frame

/// Eyebrow (+ a mono note on the right), the takeaway (bold lead + muted rest), then the chart.
struct TrendsTakeawayCard<Content: View>: View {
    let eyebrow: String
    var meta: String? = nil
    let lead: String
    let rest: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: eyebrow)
                Spacer(minLength: 8)
                if let meta {
                    Text(meta)
                        .font(Twin.Typeface.meta)
                        .tracking(0.4)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                }
            }
            (Text(lead + " ").font(Twin.Typeface.sans(16, .bold)).foregroundColor(Twin.Palette.ink)
                + Text(rest).font(Twin.Typeface.sans(16)).foregroundColor(Twin.Palette.inkMuted))
                .fixedSize(horizontal: false, vertical: true)
                .id(lead + rest)
                .transition(.opacity)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            content()
                .padding(.top, 14)
        }
        .twinCard()
    }
}

/// Runs `action` once, the first time the view scrolls into sight (iOS 18; on iOS 17 when it appears),
/// so a chart far down the page grows when it is seen, not while it is off screen.
struct TrendsOnFirstSight: ViewModifier {
    let action: () -> Void
    @State private var done = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.3) { visible in
                guard visible, !done else { return }
                done = true
                action()
            }
        } else {
            content.onAppear {
                guard !done else { return }
                done = true
                action()
            }
        }
    }
}

extension View {
    func onFirstSight(_ action: @escaping () -> Void) -> some View { modifier(TrendsOnFirstSight(action: action)) }
}

/// A dot for legends: orange with an ink edge (body-wash nights) or grey.
private struct LegendDot: View {
    var hot: Bool
    var body: some View {
        Circle()
            .fill(hot ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.28))
            .overlay { if hot { Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
            .frame(width: 9, height: 9)
    }
}

/// "- - - your usual · 12 min" for legends.
private struct UsualKey: View {
    var body: some View {
        HStack(spacing: 5) {
            ChartHLine()
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 18, height: 2)
            Text("usual · \(StageStory.usual) min")
        }
    }
}

// MARK: - 1. Weather vs scratching

/// One dot per night: humidity (or the day's high) across, minutes of scratching up. Body-wash nights
/// are orange. Dry days (and hot days) get a soft band, so you can see they were calm.
struct TrendsWeatherCard: View {
    enum Measure: String, CaseIterable, Hashable {
        case humidity, temperature
        var title: String { self == .humidity ? "Humidity" : "Temperature" }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measure: Measure = TrendsLaunch.weather ?? .humidity
    @State private var shown = false

    private let plotHeight: CGFloat = 196
    private let yAxisWidth: CGFloat = 24
    private let yTop = 45.0
    private var nights: [StageHistory.Night] { StageHistory.nights }

    private var domain: ClosedRange<Double> { measure == .humidity ? 20...80 : 55...95 }
    private var ticks: [Double] { measure == .humidity ? [20, 35, 50, 65, 80] : [55, 65, 75, 85, 95] }
    /// The soft band: dry (under 35%) or hot (85 °F and up).
    private var band: ClosedRange<Double> { measure == .humidity ? 20...Double(StageStory.dryBelowPercent) : 85...95 }
    private func value(_ n: StageHistory.Night) -> Double { Double(measure == .humidity ? n.humidity : n.highF) }

    /// Dry (or hot) days without the body wash: all calm.
    private var calmInBand: (count: Int, allCalm: Bool) {
        let list = nights.filter { !$0.bodyWash && band.contains(value($0)) }
        return (list.count, list.allSatisfy { $0.minutes <= StageStory.usual + 2 })
    }

    private var takeaway: (String, String) {
        let c = calmInBand
        let tail = nights.filter(\.flare).allSatisfy(\.bodyWash) ? " Every high night was a body-wash night." : ""
        switch measure {
        case .humidity:
            return ("No link to humidity.",
                    (c.allCalm ? "All \(c.count) dry days before the body wash were calm." : "Dry days were mixed.") + tail)
        case .temperature:
            return ("No link to temperature.",
                    (c.allCalm ? "The \(c.count) hottest days (85°F+) were calm." : "Hot days were mixed.") + tail)
        }
    }

    var body: some View {
        let t = takeaway
        TrendsTakeawayCard(eyebrow: "Weather vs scratching", meta: "\(nights.count) NIGHTS", lead: t.0, rest: t.1) {
            VStack(alignment: .leading, spacing: 12) {
                ChartRangePicker(options: Measure.allCases, selection: $measure.animation(Twin.Motion.spring), title: \.title)
                plot
                legend
            }
        }
        .animation(.easeOut(duration: 0.25), value: measure)
        .onFirstSight {
            withAnimation(reduceMotion ? .easeOut(duration: 0.35) : .linear(duration: 0.01)) { shown = true }
        }
    }

    private var plot: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width - yAxisWidth
                let x = { (v: Double) in yAxisWidth + CGFloat((v - domain.lowerBound) / (domain.upperBound - domain.lowerBound)) * w }
                let y = { (m: Double) in plotHeight - CGFloat(m / yTop) * plotHeight }
                ZStack(alignment: .topLeading) {
                    // Dry / hot band.
                    Rectangle()
                        .fill(Twin.Palette.orangeSoft.opacity(0.75))
                        .frame(width: x(band.upperBound) - x(band.lowerBound), height: plotHeight)
                        .offset(x: x(band.lowerBound))
                    Text(measure == .humidity ? "DRY" : "HOT")
                        .font(Twin.Typeface.mono(9, bold: true))
                        .tracking(0.45)
                        .foregroundStyle(Twin.Palette.orangeStrong)
                        .offset(x: x(band.lowerBound) + 5, y: 5)
                    // Grid: 24 and 36 faint, the usual dashed, the baseline.
                    ForEach([24.0, 36.0], id: \.self) { m in
                        Rectangle().fill(Twin.Palette.hairline.opacity(0.6))
                            .frame(width: w, height: 1).offset(x: yAxisWidth, y: y(m))
                    }
                    ChartHLine()
                        .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: w, height: 2)
                        .offset(x: yAxisWidth, y: y(Double(StageStory.usual)) - 1)
                    Rectangle().fill(Twin.Palette.hairline).frame(width: w, height: 1).offset(x: yAxisWidth, y: plotHeight)
                    ForEach([0.0, 12, 24, 36], id: \.self) { m in
                        Text("\(Int(m))")
                            .font(Twin.Typeface.mono(9))
                            .foregroundStyle(Twin.Palette.inkHint)
                            .frame(width: yAxisWidth - 6, alignment: .trailing)
                            .offset(y: y(m) - 6)
                    }
                    // Calm nights first, body-wash nights on top.
                    ForEach(nights.filter { !$0.bodyWash } + nights.filter(\.bodyWash)) { n in
                        dot(n, at: CGPoint(x: x(value(n)) + jitter(n), y: y(Double(n.minutes))))
                    }
                    lastNightLabel(x: x(value(StageHistory.night(StageStory.lastNightIndex))),
                                   y: y(Double(StageStory.LastNight.minutes)))
                }
            }
            .frame(height: plotHeight)
            // X axis.
            GeometryReader { g in
                let w = g.size.width - yAxisWidth
                ZStack(alignment: .topLeading) {
                    ForEach(ticks, id: \.self) { v in
                        Text(measure == .humidity ? "\(Int(v))%" : "\(Int(v))°")
                            .font(Twin.Typeface.mono(9))
                            .foregroundStyle(Twin.Palette.inkHint)
                            .fixedSize()
                            .frame(width: 40)
                            .offset(x: yAxisWidth + CGFloat((v - domain.lowerBound) / (domain.upperBound - domain.lowerBound)) * w - 20)
                    }
                }
            }
            .frame(height: 12)
            HStack {
                Text("MIN / NIGHT ↑")
                Spacer()
                Text(measure == .humidity ? "HUMIDITY THAT DAY →" : "HIGH THAT DAY, °F →")
            }
            .font(Twin.Typeface.mono(9, bold: true))
            .tracking(0.45)
            .foregroundStyle(Twin.Palette.inkHint)
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func dot(_ n: StageHistory.Night, at p: CGPoint) -> some View {
        let size: CGFloat = n.bodyWash ? 12 : 9
        let k = n.id - StageHistory.firstNight
        return Circle()
            .fill(n.bodyWash ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.28))
            .overlay { if n.bodyWash { Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1.5) } }
            .frame(width: size, height: size)
            .scaleEffect(shown || reduceMotion ? 1 : 0.01)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(0.1 + Double(k) * 0.012), value: shown)
            .offset(x: p.x - size / 2, y: p.y - size / 2)
    }

    private func lastNightLabel(x: CGFloat, y: CGFloat) -> some View {
        Text("LAST NIGHT · \(StageStory.LastNight.minutes)")
            .font(Twin.Typeface.mono(9, bold: true))
            .tracking(0.3)
            .foregroundStyle(Twin.Palette.ink)
            .fixedSize()
            .offset(x: x + 10, y: y - 6)
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(1.2), value: shown)
    }

    /// A small fixed sideways nudge so nights with the same numbers don't hide each other.
    private func jitter(_ n: StageHistory.Night) -> CGFloat { CGFloat((abs(n.id) * 37) % 7 - 3) * 0.7 }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { LegendDot(hot: true); Text("body-wash nights") }
            HStack(spacing: 5) { LegendDot(hot: false); Text("other nights") }
            UsualKey()
        }
        .font(Twin.Typeface.mono(10))
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let t = takeaway
        return "Scratching against \(measure == .humidity ? "humidity" : "temperature"), one dot per night. \(t.0) \(t.1)"
    }
}

// MARK: - 5. Weekday pattern

/// Average minutes per weekday before the body wash, with your usual and a ±2 min band.
struct TrendsWeekdayCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var now = Date()

    private let plotHeight: CGFloat = 120
    private let top = 16.0
    private let names = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        let averages = StageHistory.weekdayAverages(now: now, calendar: TodayStory.calendar)
        let usual = Double(StageStory.usual)
        let spread = averages.map { abs($0 - usual) }.max() ?? 0
        let flat = spread <= 2
        TrendsTakeawayCard(eyebrow: "By weekday", meta: "\(StageHistory.beforeBodyWash.count) NIGHTS BEFORE THE WASH",
                           lead: flat ? "No weekday pattern." : "Some days run higher.",
                           rest: flat ? "Every day is within 2 min of your usual." : "Weekends differ from weekdays.") {
            VStack(spacing: 6) {
                chart(averages, usual: usual)
                Rectangle().fill(Twin.Palette.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    ForEach(names, id: \.self) { n in
                        Text(n).font(Twin.Typeface.mono(9)).foregroundStyle(Twin.Palette.inkHint).frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Twin.Palette.limeSoft)
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.hairline, lineWidth: 1))
                            .frame(width: 14, height: 9)
                        Text("usual ± 2 min")
                    }
                    UsualKey()
                    Spacer(minLength: 0)
                }
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
        }
        .onFirstSight {
            if reduceMotion { withAnimation(.easeOut(duration: 0.35)) { grown = true } } else { grown = true }
        }
        .onNewDay { now = Date() }
        .accessibilityElement(children: .combine)
    }

    private func chart(_ averages: [Double], usual: Double) -> some View {
        GeometryReader { g in
            let slot = g.size.width / 7
            let y = { (m: Double) in plotHeight - CGFloat(m / top) * plotHeight }
            ZStack(alignment: .topLeading) {
                // Usual ± 2 min.
                Rectangle()
                    .fill(Twin.Palette.limeSoft.opacity(0.8))
                    .frame(width: g.size.width, height: y(usual - 2) - y(usual + 2))
                    .offset(y: y(usual + 2))
                    .opacity(grown ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: grown)
                ForEach(0..<7, id: \.self) { d in
                    let v = averages[d]
                    let h = max(3, plotHeight - y(v))
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // Opaque, so the usual band behind doesn't tint the bars.
                        shape.fill(Twin.Palette.fillStrong)
                            .frame(width: min(30, slot * 0.56), height: h)
                            .overlay(alignment: .bottom) {
                                Text(String(format: "%.0f", v))
                                    .font(Twin.Typeface.mono(11, bold: true))
                                    .foregroundStyle(Twin.Palette.ink)
                                    .padding(.bottom, 6)
                                    .opacity(grown ? 1 : 0)
                                    .animation(.easeOut(duration: 0.3).delay(0.45 + Double(d) * 0.05), value: grown)
                            }
                            .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                            .opacity(grown ? 1 : 0)
                            .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(0.15 + Double(d) * 0.05), value: grown)
                    }
                    .frame(width: slot, height: plotHeight)
                    .offset(x: slot * CGFloat(d))
                }
                ChartHLine()
                    .trim(from: 0, to: grown ? 1 : 0)
                    .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: g.size.width, height: 2)
                    .offset(y: y(usual) - 1)
                    .animation(.easeOut(duration: 0.6).delay(0.6), value: grown)
            }
        }
        .frame(height: plotHeight)
    }
}
