import SwiftUI
import EczemaKit

/// Today's episodes (tap the hero card): totals, a 24-hour "seismograph" of every episode
/// (intense ones orange and taller), then each episode with time, length, rate and a flame.
struct TodayEpisodesSheet: View {
    let snap: TodaySnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Part: Identifiable {
        let id: Int
        let title: String
        let hours: String
        let episodes: [ScratchEpisode]
        var minutes: Double { episodes.reduce(0) { $0 + $1.duration } / 60 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)
            Rectangle().fill(Twin.Palette.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stats.riseIn(0.05, distance: reduceMotion ? 0 : 12)
                    seismograph.riseIn(0.12, distance: reduceMotion ? 0 : 12)
                    if snap.episodes.isEmpty {
                        Text("No episodes so far today.")
                            .font(Twin.Typeface.sans(15))
                            .foregroundStyle(Twin.Palette.inkMuted)
                    }
                    ForEach(Array(parts.enumerated()), id: \.element.id) { i, part in
                        partSection(part).riseIn(0.18 + Double(i) * 0.06, distance: reduceMotion ? 0 : 12)
                    }
                    Text("Times come from your watch. Tap No on the watch when it guesses wrong, and it learns.")
                        .font(Twin.Typeface.sans(12))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Twin.Palette.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Twin.Radius.dialog)
        .presentationBackground(Twin.Palette.paper)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today's episodes").font(Twin.Typeface.title).foregroundStyle(Twin.Palette.ink)
                Text(TodayTrends.Format.weekdayDay(snap.day.day))
                    .font(Twin.Typeface.meta).tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 32, height: 32)
                    .sticker(Twin.Palette.paper, radius: Twin.Radius.control)
                    .contentShape(TapAreaShape(dx: 6, dy: 6))   // 44 × 44 pt tap area, same 32 pt look
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
        }
    }

    // MARK: Totals

    private var stats: some View {
        HStack(spacing: 0) {
            stat(value: snap.minutes.rounded(), label: "Minutes", color: Twin.Palette.ink)
            divider
            stat(value: Double(snap.episodeCount), label: "Episodes", color: Twin.Palette.ink)
            divider
            stat(value: Double(snap.intenseCount), label: "Intense", color: Twin.Palette.ink, flame: true)
        }
        .padding(.vertical, 12)
        .background(Twin.Palette.cream, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }

    private var divider: some View {
        Rectangle().fill(Twin.Palette.hairline).frame(width: 1, height: 34)
    }

    private func stat(value: Double, label: String, color: Color, flame: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if flame {
                    Image(systemName: "flame.fill").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Twin.Palette.orange)
                }
                CountUp(value: value, font: Twin.Typeface.sans(26, .bold), color: color, delay: 0.15, duration: 0.9)
                    .tracking(-0.8)
            }
            Text(label.uppercased()).font(Twin.Typeface.mono(10)).tracking(0.6).foregroundStyle(Twin.Palette.inkHint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: 24-hour seismograph

    private var seismograph: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Every episode today")
            TodaySeismograph(episodes: snap.episodes, dayStart: snap.day.day, now: snap.nowHour)
                .frame(height: 64)
        }
    }

    // MARK: List

    private var parts: [Part] {
        let cal = Calendar.current
        let ranges: [(Int, String, String, ClosedRange<Int>)] = [
            (0, "Night", "12–6 am", 0...5), (1, "Morning", "6 am–12 pm", 6...11),
            (2, "Afternoon", "12–6 pm", 12...17), (3, "Evening", "6 pm–12 am", 18...23),
        ]
        return ranges.compactMap { id, title, hours, r in
            let eps = snap.episodes.filter { r.contains(cal.component(.hour, from: $0.start)) }
            return eps.isEmpty ? nil : Part(id: id, title: title, hours: hours, episodes: eps)
        }
    }

    private func partSection(_ part: Part) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(part.title).font(Twin.Typeface.headline).foregroundStyle(Twin.Palette.ink)
                Text(part.hours.uppercased()).font(Twin.Typeface.meta).foregroundStyle(Twin.Palette.inkHint)
                Spacer()
                Text("\(Int(part.minutes.rounded())) MIN · \(part.episodes.count)×")
                    .font(Twin.Typeface.mono(11, bold: true))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            .padding(.bottom, 6)
            let longest = max(part.episodes.map(\.duration).max() ?? 1, 1)
            ForEach(part.episodes) { e in
                row(e, longest: longest)
                if e.id != part.episodes.last?.id {
                    Rectangle().fill(Twin.Palette.hairline).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .twinCard(padding: 0)
    }

    private func row(_ e: ScratchEpisode, longest: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text(TodayTrends.Format.clock(e.start))
                .font(Twin.Typeface.mono(13))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 70, alignment: .leading)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Twin.Palette.fill)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(e.intense ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.3))
                    .frame(width: max(4, 56 * CGFloat(e.duration / longest)))
            }
            .frame(width: 56, height: 6)
            Text(TodayTrends.Format.duration(e.duration))
                .font(Twin.Typeface.sans(14, .medium))
                .foregroundStyle(Twin.Palette.ink)
            Spacer(minLength: 4)
            Text(String(format: "%.1f Hz", e.meanHz))
                .font(Twin.Typeface.mono(11))
                .foregroundStyle(Twin.Palette.inkHint)
            Image(systemName: e.intense ? "flame.fill" : "flame")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(e.intense ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.18))
                .frame(width: 18)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(TodayTrends.Format.clock(e.start)), \(TodayTrends.Format.duration(e.duration))\(e.intense ? ", intense" : "")")
    }
}

/// Every episode of a day as a tick on a 24-hour line (intense = orange and taller).
/// Ticks rise in from left to right, like a seismograph being drawn.
struct TodaySeismograph: View {
    let episodes: [ScratchEpisode]
    let dayStart: Date
    let now: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotH = geo.size.height - 18
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Twin.Palette.hairline).frame(width: w, height: 1).offset(y: plotH)
                ForEach(episodes) { e in
                    let t = e.start.timeIntervalSince(dayStart) / 3600
                    let x = CGFloat(t / 24) * w
                    let h: CGFloat = e.intense ? plotH : plotH * 0.62
                    Rectangle()
                        .fill(e.intense ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.38))
                        .frame(width: e.intense ? 2.5 : 1.5, height: h)
                        .scaleEffect(y: drawn || reduceMotion ? 1 : 0, anchor: .bottom)
                        .opacity(drawn ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.spring.delay(0.2 + t / 24 * 0.8), value: drawn)
                        .offset(x: x, y: plotH - h)
                }
                if let now {
                    let x = CGFloat(now / 24) * w
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Twin.Palette.yellow)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                        .frame(width: 9, height: 9)
                        .offset(x: x - 4.5, y: plotH - 4.5)
                        .opacity(drawn ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(1.0), value: drawn)
                }
                HStack(spacing: 0) {
                    ForEach(["12a", "6a", "12p", "6p"], id: \.self) { label in
                        Text(label).font(Twin.Typeface.mono(10)).foregroundStyle(Twin.Palette.inkHint)
                            .frame(width: w / 4, alignment: .leading)
                    }
                }
                .offset(y: plotH + 5)
            }
        }
        .onAppear { drawn = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(episodes.count) episodes today, \(episodes.filter(\.intense).count) intense")
    }
}
