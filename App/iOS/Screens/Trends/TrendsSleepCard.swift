import SwiftUI
import EczemaKit

// MARK: - 3. Scratching over sleep (last night)

/// Last night's sleep stages (Awake / REM / Core / Deep rows, Apple Health style) from 11:04 PM to
/// 6:52 AM, with the quarter-hour scratching bars under them on the same clock. Each wake-up has a
/// numbered sticker, and the scratching bout just before it is shaded across both, so you can see
/// the scratching came first.
struct TrendsSleepCard: View {
    typealias Sleep = StageHistory.LastNightSleep

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let labelWidth: CGFloat = 46
    private let markerBand: CGFloat = 22
    private let rowHeight: CGFloat = 20
    private let rowGap: CGFloat = 6
    private let laneGap: CGFloat = 16
    private let laneHeight: CGFloat = 34
    private let reveal = 1.4

    private let rows: [Sleep.Stage] = [.awake, .rem, .core, .deep]
    private var stagesHeight: CGFloat { CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowGap }
    private var laneTop: CGFloat { markerBand + stagesHeight + laneGap }
    private var totalHeight: CGFloat { laneTop + laneHeight }
    private var wakes: [Sleep.Segment] { Sleep.wakeUps }

    var body: some View {
        let after = Sleep.wakeUpsAfterScratching
        TrendsTakeawayCard(eyebrow: "Last night · sleep and scratching",
                           lead: "\(after) of \(wakes.count) wake-ups",
                           rest: after == wakes.count ? "came right after a scratching bout." : "came right after a scratching bout; the rest didn't.") {
            VStack(alignment: .leading, spacing: 8) {
                chart
                axis
                summary.padding(.top, 6)
            }
        }
        .onFirstSight {
            withAnimation(reduceMotion ? .easeOut(duration: 0.35) : .easeInOut(duration: reveal)) { shown = true }
        }
    }

    private func x(_ t: Double, _ w: CGFloat) -> CGFloat { labelWidth + CGFloat(t / Double(Sleep.length)) * w }
    private func rowY(_ s: Sleep.Stage) -> CGFloat {
        markerBand + CGFloat(rows.firstIndex(of: s) ?? 0) * (rowHeight + rowGap)
    }

    private static func fill(_ s: Sleep.Stage) -> Color {
        switch s {
        case .awake: return Twin.Palette.pink
        case .rem: return Twin.Palette.cyanSoft
        case .core: return Twin.Palette.cyan
        case .deep: return Twin.Palette.cyanStrong
        }
    }

    private static func name(_ s: Sleep.Stage) -> String {
        switch s {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    private var chart: some View {
        GeometryReader { g in
            let w = g.size.width - labelWidth
            ZStack(alignment: .topLeading) {
                // The bout before each wake-up, shaded over the stages and the scratching lane.
                ForEach(Array(wakes.enumerated()), id: \.offset) { k, wake in
                    let q = Sleep.quarter(at: wake.start - 5)
                    let from = max(0, Double(q * 15 - Sleep.offsetIntoFirstQuarter))
                    Rectangle()
                        .fill(Twin.Palette.orangeSoft)
                        .frame(width: max(2, x(Double(wake.start), w) - x(from, w)), height: totalHeight - markerBand + 4)
                        .offset(x: x(from, w), y: markerBand - 2)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(stickerDelay(wake)), value: shown)
                }
                // Row guides and labels.
                ForEach(rows, id: \.self) { s in
                    Rectangle().fill(Twin.Palette.hairline.opacity(0.5))
                        .frame(width: w, height: 1)
                        .offset(x: labelWidth, y: rowY(s) + rowHeight / 2)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Self.fill(s))
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: 1))
                            .frame(width: 8, height: 8)
                        Text(Self.name(s))
                            .font(Twin.Typeface.sans(11, .medium))
                            .foregroundStyle(Twin.Palette.inkMuted)
                    }
                    .frame(height: rowHeight)
                    .offset(y: rowY(s))
                }
                Text("Scratch")
                    .font(Twin.Typeface.sans(11, .medium))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .frame(height: laneHeight, alignment: .bottom)
                    .offset(y: laneTop)
                // The hypnogram and the scratching lane, revealed left to right.
                ZStack(alignment: .topLeading) {
                    connectors(w)
                    ForEach(Array(Sleep.segments.enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.fill(seg.stage))
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: 1))
                            .frame(width: max(3, x(Double(seg.end), w) - x(Double(seg.start), w)), height: rowHeight)
                            .offset(x: x(Double(seg.start), w), y: rowY(seg.stage))
                    }
                    lane(w)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: shown || reduceMotion ? g.size.width : labelWidth)
                }
                // Wake-up stickers.
                ForEach(Array(wakes.enumerated()), id: \.offset) { k, wake in
                    Text("\(k + 1)")
                        .font(Twin.Typeface.mono(10, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .frame(width: 17, height: 17)
                        .sticker(Twin.Palette.paper)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.5, anchor: .bottom)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(stickerDelay(wake)), value: shown)
                        .offset(x: x(Double(wake.start), w) - 8.5, y: 0)
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func stickerDelay(_ wake: Sleep.Segment) -> Double {
        reduceMotion ? 0 : reveal * Double(wake.start) / Double(Sleep.length) + 0.1
    }

    /// Thin vertical lines joining one stage to the next (Apple Health style).
    private func connectors(_ w: CGFloat) -> some View {
        Path { p in
            for (a, b) in zip(Sleep.segments, Sleep.segments.dropFirst()) {
                let xx = x(Double(a.end), w)
                let y1 = rowY(a.stage) + rowHeight / 2, y2 = rowY(b.stage) + rowHeight / 2
                p.move(to: CGPoint(x: xx, y: min(y1, y2)))
                p.addLine(to: CGPoint(x: xx, y: max(y1, y2)))
            }
        }
        .stroke(Twin.Palette.ink.opacity(0.45), lineWidth: 1)
    }

    /// The 32 quarter-hour bars (minutes of scratching), on the same clock as the stages.
    private func lane(_ w: CGFloat) -> some View {
        let buckets = StageStory.LastNight.quarterHours
        let top = max(buckets.max() ?? 1, 1)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Twin.Palette.hairline).frame(width: w, height: 1)
                .offset(x: labelWidth, y: laneTop + laneHeight)
            ForEach(buckets.indices, id: \.self) { q in
                let from = max(0, Double(q * 15 - Sleep.offsetIntoFirstQuarter))
                let to = min(Double(Sleep.length), Double(q * 15 + 15 - Sleep.offsetIntoFirstQuarter))
                let m = buckets[q]
                if m > 0.05, to > from {
                    let h = max(2, CGFloat(m / top) * (laneHeight - 2))
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
                    shape.fill(m >= 1 ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.18))
                        .overlay { if m >= 1 { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
                        .frame(width: max(2, x(to, w) - x(from, w) - 2), height: h)
                        .offset(x: x(from, w) + 1, y: laneTop + laneHeight - h)
                }
            }
        }
    }

    /// 12a … 6a under the chart.
    private var axis: some View {
        GeometryReader { g in
            let w = g.size.width - labelWidth
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { h in
                    let t = Double(56 + h * 60)   // midnight is 56 min after 11:04 PM
                    Text(h == 0 ? "12a" : "\(h)a")
                        .font(Twin.Typeface.mono(9))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: x(t, w) - 15)
                }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Text("\(StageStory.LastNight.asleep) – \(StageStory.LastNight.awake)")
            Spacer(minLength: 8)
            Text(String(format: "%.1f H ASLEEP · %d MIN SCRATCHING", Double(Sleep.minutesAsleep) / 60, StageStory.LastNight.minutes))
        }
        .font(Twin.Typeface.mono(10))
        .tracking(0.3)
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var accessibilityText: String {
        let times = wakes.map { clock($0.start) }.joined(separator: ", ")
        return "Last night's sleep stages with scratching. You woke up at \(times). "
            + "\(Sleep.wakeUpsAfterScratching) of \(wakes.count) wake-ups came right after a scratching bout."
    }

    /// "1:28 AM" for minute `t` after 11:04 PM.
    private func clock(_ t: Int) -> String {
        let total = (23 * 60 + 4 + t) % (24 * 60)
        let h = total / 60, m = total % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }
}
