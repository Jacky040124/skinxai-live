import SwiftUI
import EczemaKit

/// "Scratching today": the ring (today ÷ 3 × usual) with counted minutes, the "× your usual"
/// sticker that stamps in, when it happened most, and the 24-hour chart with a "now" marker.
struct TodayHeroCard: View {
    let snap: TodaySnapshot

    private let ringSize: CGFloat = 142
    private let ringLine: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Eyebrow(text: "Scratching today")
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Text("EPISODES").font(Twin.Typeface.mono(10, bold: true)).tracking(0.6)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Twin.Palette.inkHint)
            }

            HStack(alignment: .center, spacing: 18) {
                ring
                VStack(alignment: .leading, spacing: 10) {
                    TodayRatioSticker(ratio: snap.ratio, level: snap.level)
                    summary
                        .fixedSize(horizontal: false, vertical: true)
                    if snap.usual > 0 {
                        Text("YOUR USUAL · \(Int(snap.usual.rounded())) MIN")
                            .font(Twin.Typeface.mono(10))
                            .tracking(0.6)
                            .foregroundStyle(Twin.Palette.inkHint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HourlyScratchChart(minutes: snap.day.scratchMinutesByHour,
                               hot: snap.pattern.hot,
                               accent: snap.accent,
                               now: snap.nowHour,
                               scaleMax: snap.hourScaleMax,
                               plotHeight: 88,
                               delay: 0.3)
                .padding(.top, 4)
        }
        .twinCard()
        .contentShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            RingView(progress: snap.ringProgress, lineWidth: ringLine, color: snap.accent,
                     track: Twin.Palette.fill, delay: 0.18)
            VStack(spacing: 0) {
                CountUp(value: snap.minutes.rounded(), font: Twin.Typeface.sans(46, .bold), delay: 0.18, duration: 1.2)
                    .tracking(-1.5)
                Text("MIN").font(Twin.Typeface.mono(11)).foregroundStyle(Twin.Palette.inkHint)
                    .offset(y: -2)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    // MARK: Text

    private var summary: Text {
        let counts = countsLine
        guard let phrase = snap.pattern.phrase else {
            return Text(snap.minutes < 0.5 ? "No scratching so far today." : counts)
                .font(Twin.Typeface.sans(14))
                .foregroundColor(Twin.Palette.inkMuted)
        }
        return (Text("\(phrase.lead), ")
            + Text(phrase.range).font(Twin.Typeface.sans(14, .bold)).foregroundColor(Twin.Palette.ink)
            + Text(". \(counts)"))
            .font(Twin.Typeface.sans(14))
            .foregroundColor(Twin.Palette.inkMuted)
    }

    private var countsLine: String {
        let e = TodayTrends.Format.count(snap.episodeCount, "episode")
        if snap.episodeCount == 0 { return "No episodes yet." }
        return snap.intenseCount == 0 ? "\(e), none intense." : "\(e), \(snap.intenseCount) intense."
    }

    private var accessibilityText: String {
        var parts = ["Scratching today: \(Int(snap.minutes.rounded())) minutes"]
        switch snap.level {
        case .above: parts.append(String(format: "%.1f times your usual", snap.ratio))
        case .usual: parts.append("a normal day")
        case .calmer: parts.append("calmer than usual")
        }
        if let p = snap.pattern.phrase { parts.append("\(p.lead), \(p.range)") }
        parts.append(countsLine)
        return parts.joined(separator: ". ")
    }
}

/// "▲ 4.1× your usual" (orange) · "✓ Normal day" (lime) · "▼ Calmer than usual" (lime).
/// Stamps in with a little rotation once the ring has filled; the multiplier counts up.
struct TodayRatioSticker: View {
    let ratio: Double
    let level: TodayTrends.Level
    var delay: Double = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    /// The multiplier counts up from 1× (your usual) to today's value.
    @State private var shownRatio: Double = 1

    var body: some View {
        HStack(spacing: 5) {
            switch level {
            case .above:
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9, weight: .bold))
                HStack(spacing: 0) {
                    CountingText(value: shownRatio, decimals: ratio >= 10 ? 0 : 1, font: Twin.Typeface.sans(13, .bold))
                    Text("× your usual")
                }
            case .usual:
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                Text("Normal day")
            case .calmer:
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9, weight: .bold))
                Text("Calmer than usual")
            }
        }
        .font(Twin.Typeface.sans(13, .bold))
        .foregroundStyle(Twin.Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sticker(level == .above ? Twin.Palette.orange : Twin.Palette.lime)
        .scaleEffect(stamped || reduceMotion ? 1 : 0.55, anchor: .leading)
        .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -9), anchor: .leading)
        .opacity(stamped ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : Twin.Motion.bouncy.delay(delay)) { stamped = true }
            withAnimation(.easeOut(duration: 0.9).delay(delay + 0.05)) { shownRatio = ratio }
        }
        .onChange(of: ratio) { _, new in withAnimation(.easeOut(duration: 0.9)) { shownRatio = new } }
    }
}
