import SwiftUI
import EczemaKit

/// "Last night": when he slept, the ring with the minutes of scratching (counting up while the ring
/// fills), the "× your usual" sticker that stamps in, the worst hours, and the night in 32 quarter-hour
/// bars that grow in one after another (the bad stretch orange).
struct TodayNightCard: View {
    private typealias Last = StageStory.LastNight

    private let ringSize: CGFloat = 142
    private let ringLine: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(text: "Last night")
                Spacer(minLength: 8)
                Text(TodayStory.sleepWindow)
                    .font(Twin.Typeface.eyebrow)
                    .tracking(0.3)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 8) {
                    TodayRatioSticker(ratio: TodayStory.ratio)
                    summary
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("YOUR USUAL · \(StageStory.usual) MIN")
                        .font(Twin.Typeface.mono(11))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)

            QuarterHourChart(values: Last.quarterHours, hotAbove: TodayStory.hotQuarterHour,
                             labels: TodayStory.quarterHourLabels, plotHeight: 86, delay: 0.3)
                .padding(.top, 14)
        }
        .twinCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The minutes count up while the ring fills (full at 3.6 × your usual).
    private var ring: some View {
        ZStack {
            RingView(progress: TodayStory.ringProgress, lineWidth: ringLine, color: Twin.Palette.orange, delay: 0.12)
            VStack(spacing: 0) {
                CountUp(value: Double(Last.minutes), font: Twin.Typeface.sans(46, .bold), delay: 0.12, duration: 1.2)
                    .tracking(-1.5)
                Text("MIN")
                    .font(Twin.Typeface.mono(11))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .offset(y: -2)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    /// "Worst **2–4 AM**." / "23 episodes, 7 intense."
    private var summary: Text {
        (Text("Worst ")
            + Text(Last.worst).font(Twin.Typeface.sans(15, .bold)).foregroundColor(Twin.Palette.ink)
            + Text(".\n\(Last.episodes)\u{00A0}episodes, \(Last.intense)\u{00A0}intense."))
            .font(Twin.Typeface.sans(15))
            .foregroundColor(Twin.Palette.inkMuted)
    }

    private var accessibilityText: String {
        "Last night, \(Last.asleep) to \(Last.awake): \(Last.minutes) minutes of scratching, "
            + String(format: "%.1f times your usual. ", TodayStory.ratio)
            + "Worst \(Last.worst). \(Last.episodes) episodes, \(Last.intense) intense. Your usual: \(StageStory.usual) minutes."
    }
}

/// "▲ 3.4× your usual" (orange), or "✓ About your usual" (lime) on a calm night.
/// Stamps in with a little turn once the ring has filled; the multiplier counts up from 1×.
struct TodayRatioSticker: View {
    let ratio: Double
    var delay: Double = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    /// The multiplier counts up from 1× (your usual) to last night's value.
    @State private var shownRatio: Double = 1

    private var above: Bool { ratio > 1.25 }

    var body: some View {
        HStack(spacing: 5) {
            if above {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9, weight: .bold))
                HStack(spacing: 0) {
                    CountingText(value: shownRatio, decimals: ratio >= 10 ? 0 : 1, font: Twin.Typeface.sans(13, .bold))
                    Text("× your usual")
                }
            } else {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                Text("About your usual")
            }
        }
        .font(Twin.Typeface.sans(13, .bold))
        .foregroundStyle(Twin.Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sticker(above ? Twin.Palette.orange : Twin.Palette.lime)
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
