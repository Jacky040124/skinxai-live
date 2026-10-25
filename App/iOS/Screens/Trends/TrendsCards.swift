import SwiftUI
import EczemaKit

// MARK: - Week sticker

/// "▲ up 91% from last week" (orange) · "▼ down 20% from last week" (lime) · "About the same as
/// last week". Stamps in like Today's "× your usual" sticker, then the percent counts up from 0.
struct TrendsWeekSticker: View {
    /// This week's average against last week's, percent (91 = up 91%).
    let percent: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    @State private var shownPct: Double = 0

    private static let stampDelay = 0.6

    private var up: Bool { percent >= 10 }
    private var down: Bool { percent <= -10 }

    var body: some View {
        sticker
            .scaleEffect(stamped || reduceMotion ? 1 : 0.55, anchor: .leading)
            .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -8), anchor: .leading)
            .opacity(stamped ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(Self.stampDelay)
                                           : Twin.Motion.bouncy.delay(Self.stampDelay)) { stamped = true }
                withAnimation(.easeOut(duration: 0.9).delay(Self.stampDelay + 0.05)) { shownPct = Double(abs(percent)) }
            }
            .onChange(of: percent) { _, new in withAnimation(.easeOut(duration: 0.9)) { shownPct = Double(abs(new)) } }
    }

    @ViewBuilder private var sticker: some View {
        if up || down {
            HStack(spacing: 5) {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 10, weight: .bold))
                HStack(spacing: 0) {
                    Text(up ? "up " : "down ")
                    CountingText(value: shownPct, decimals: 0, font: Twin.Typeface.sans(12, .bold))
                    Text("% from last week")
                }
                .font(Twin.Typeface.sans(12, .bold))
                .lineLimit(1)
            }
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .sticker(up ? Twin.Palette.orange : Twin.Palette.lime)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(up ? "Up" : "Down") \(abs(percent))% from last week")
        } else {
            Sticker(text: "About the same as last week", icon: "equal", fill: Twin.Palette.paper)
        }
    }
}

// MARK: - Detail strip of the selected night

/// Cyan strip under the chart ("this item"): the selected night. The numbers roll and the sticker
/// swaps when the selection moves.
struct TrendsNightDetail: View {
    let night: TrendsNight

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(night.eyebrow)
                    .font(Twin.Typeface.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(night.minutes)")
                        .font(Twin.Typeface.sans(20, .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(night.minutes)))
                    Text(" min")
                        .font(Twin.Typeface.sans(20, .bold))
                    Text(" · \(night.note)")
                        .font(Twin.Typeface.callout)
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                }
                .foregroundStyle(Twin.Palette.ink)
            }
            Spacer(minLength: 8)
            Group {
                if night.hot {
                    Sticker(text: night.ratio, icon: "arrowtriangle.up.fill", fill: Twin.Palette.orange)
                } else {
                    Sticker(text: "normal", fill: Twin.Palette.lime)
                }
            }
            .id(night.hot ? night.ratio : "normal")
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.cyanSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
        .accessibilityElement(children: .combine)
    }
}
