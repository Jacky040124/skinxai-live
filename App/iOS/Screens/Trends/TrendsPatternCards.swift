import SwiftUI
import EczemaKit

// The pattern cards under the nights chart: each one is an eyebrow, one plain-English takeaway that
// says what the data shows (linked or not), and the chart. All numbers come from `StageHistory`
// (74 nights: 60 before `StageStory`'s 14).

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

// MARK: - 4. Weekday pattern

/// Average minutes per weekday outside both flares, with your usual and a ±2 min band.
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
        TrendsTakeawayCard(eyebrow: "By weekday", meta: "\(StageHistory.typicalNights.count) NIGHTS · FLARES LEFT OUT",
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
