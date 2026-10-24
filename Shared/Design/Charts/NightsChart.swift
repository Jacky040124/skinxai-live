import SwiftUI

/// Minutes of scratching per night (Trends).
///
/// - One bar per night, growing in one after another with a spring. Flare nights are orange with an
///   ink edge, the others 15% ink.
/// - A dashed "your usual" line draws itself across once the bars are up.
/// - Markers are stickers on two rows above the bars, each with a dotted stem down to the top of its
///   night's bar. A `trailing` marker ends at its stem instead of being centered on it, so a marker
///   over the last night stays inside the card.
/// - Under the bars: a hairline, the month, and the day numbers (the last night in bold).
/// - Tap a night to select it: a cyan outline moves to its bar (matchedGeometryEffect) with a
///   selection haptic.
struct NightsChart: View {
    struct Bar: Identifiable, Equatable {
        /// The night (stays the same when the range changes, so bars move instead of being replaced).
        var id: Int
        var value: Double
        var hot: Bool
        /// Day number under the bar, e.g. "20".
        var day: String
        /// Month label that starts at this bar, e.g. "OCT" (the first bar, and the 1st of a month).
        var month: String?
        var isLast = false
        /// VoiceOver description of the night.
        var accessibility = ""
    }

    struct Marker: Identifiable, Equatable {
        var id: String
        /// The `Bar.id` it points at.
        var bar: Int
        var emoji: String
        var text: String
        var fill: Color
        /// 0 = the top row, 1 = the row under it.
        var row: Int
        /// The sticker ends at the stem instead of being centered on it.
        var trailing = false
    }

    var bars: [Bar]
    var usual: Double
    /// Minutes at the top of the plot.
    var scaleTop: Double
    var markers: [Marker] = []
    @Binding var selection: Int
    var plotHeight: CGFloat = 170
    /// Room above the plot for the two marker rows.
    var markerBand: CGFloat = 64
    var gap: CGFloat = 4
    /// Bars never get wider than this (the 7-night range); they stay centered in their slot.
    var maxBarWidth: CGFloat = 34
    var delay: Double = 0.12
    var stagger: Double = 0.04

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var decorated = false

    /// Top of each marker row, from the top of the chart (the prototype's -56 and -30 above the plot).
    private var rowTops: [CGFloat] { [markerBand - 56, markerBand - 30] }
    private let flagHeight: CGFloat = 18
    private let monthGap: CGFloat = 6, monthHeight: CGFloat = 11, dayGap: CGFloat = 2, dayHeight: CGFloat = 12

    private var plotBottom: CGFloat { markerBand + plotHeight }
    private var totalHeight: CGFloat {
        plotBottom + Twin.Stroke.hairline + monthGap + monthHeight + dayGap + dayHeight
    }

    var body: some View {
        GeometryReader { g in
            let m = Metrics(width: g.size.width, count: bars.count, gap: gap, maxBar: maxBarWidth)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Twin.Palette.hairline)
                    .frame(width: m.width, height: Twin.Stroke.hairline)
                    .offset(y: plotBottom)
                ForEach(Array(bars.enumerated()), id: \.element.id) { k, bar in
                    column(bar, k: k, m: m)
                        .transition(.opacity)
                }
                usualLine(m)
                ForEach(visibleMarkers) { marker in stem(marker, m: m) }
                ForEach(Array(bars.enumerated()), id: \.element.id) { k, bar in
                    labels(bar, k: k, m: m)
                }
                // Flags last: they take their own taps above the columns' tap areas.
                ForEach(visibleMarkers) { marker in flag(marker, m: m) }
            }
            .frame(width: m.width, height: totalHeight, alignment: .topLeading)
        }
        .frame(height: totalHeight)
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true; decorated = true }
            } else {
                grown = true   // each bar, stem and flag carries its own delayed animation
                withAnimation(.easeInOut(duration: 0.7).delay(decorationDelay)) { decorated = true }
            }
        }
    }

    // MARK: Timing

    /// The usual line draws once every bar has grown.
    private var decorationDelay: Double { delay + Double(bars.count) * stagger + 0.2 }

    /// A marker drops in right after its own bar has grown.
    private func markerDelay(_ marker: Marker) -> Double {
        delay + Double(index(of: marker.bar) ?? 0) * stagger + 0.45
    }

    // MARK: Geometry

    private struct Metrics {
        let width: CGFloat
        let count: Int
        let gap: CGFloat
        let maxBar: CGFloat
        var slot: CGFloat { count > 0 ? max(1, (width - gap * CGFloat(count - 1)) / CGFloat(count)) : width }
        var bar: CGFloat { min(slot, maxBar) }
        func slotX(_ k: Int) -> CGFloat { CGFloat(k) * (slot + gap) }
        func center(_ k: Int) -> CGFloat { slotX(k) + slot / 2 }
    }

    private func height(_ value: Double) -> CGFloat {
        max(3, CGFloat(value / max(scaleTop, 0.001)) * plotHeight)
    }

    private func index(of id: Int) -> Int? { bars.firstIndex { $0.id == id } }

    private var visibleMarkers: [Marker] { markers.filter { index(of: $0.bar) != nil } }

    // MARK: Bars

    private func column(_ bar: Bar, k: Int, m: Metrics) -> some View {
        let h = height(bar.value)
        let selected = selection == bar.id
        // The bar grows out of the baseline as a render transform (its layout never changes), so the
        // spring only overshoots its own height a little; the selection outline grows with it.
        return ZStack(alignment: .bottom) {
            barShape(bar.hot)
                .frame(width: m.bar, height: h)
            if selected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Twin.Palette.cyan, lineWidth: 2)
                    .frame(width: m.bar + 8, height: h + 8)
                    .offset(y: 4)
                    .matchedGeometryEffect(id: "night-selection", in: ns)
            }
        }
        .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
        .opacity(grown ? 1 : 0)
        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(delay + Double(k) * stagger), value: grown)
        .frame(width: m.slot, height: plotHeight, alignment: .bottom)
        .offset(x: m.slotX(k), y: markerBand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibility)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(bar.id) }
    }

    @ViewBuilder private func barShape(_ hot: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
        if hot {
            shape.fill(Twin.Palette.orange).overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: 1))
        } else {
            shape.fill(Twin.Palette.ink.opacity(0.15))
        }
    }

    private func usualLine(_ m: Metrics) -> some View {
        ChartHLine()
            .trim(from: 0, to: decorated ? 1 : 0)
            .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: m.width, height: 2)
            .offset(y: plotBottom - height(usual) - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Markers

    private func stem(_ marker: Marker, m: Metrics) -> some View {
        let k = index(of: marker.bar) ?? 0
        let value = bars.indices.contains(k) ? bars[k].value : 0
        let top = rowTops[min(max(marker.row, 0), rowTops.count - 1)] + flagHeight + 4
        let length = max(0, plotBottom - height(value) - 2 - top)
        return ChartVLine()
            .trim(from: 0, to: decorated ? 1 : 0)
            .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.01, 3.2]))
            .frame(width: 2, height: length)
            .offset(x: m.center(k) - 1, y: top)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(markerDelay(marker) + 0.1), value: decorated)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func flag(_ marker: Marker, m: Metrics) -> some View {
        let k = index(of: marker.bar) ?? 0
        let x = marker.trailing ? m.center(k) + 6 : m.center(k)
        return Button { select(marker.bar) } label: {
            HStack(spacing: 3) {
                Text(marker.emoji).font(.system(size: 10))
                Text(marker.text).font(Twin.Typeface.sans(10, .bold)).lineLimit(1)
            }
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 5)
            .frame(height: flagHeight)
            .sticker(marker.fill)
            .fixedSize()
            .contentShape(TapAreaShape(dx: 3, dy: 4))
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(decorated || reduceMotion ? 1 : 0.6, anchor: .bottom)
        .opacity(decorated ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(markerDelay(marker)), value: decorated)
        .frame(width: 0, alignment: marker.trailing ? .trailing : .center)
        .offset(x: x, y: rowTops[min(max(marker.row, 0), rowTops.count - 1)])
        .accessibilityHidden(true)   // each bar's own label names its marker
    }

    // MARK: Labels and taps

    /// The month and day under a bar, and the night's tap area (its whole column).
    private func labels(_ bar: Bar, k: Int, m: Metrics) -> some View {
        let monthY = plotBottom + Twin.Stroke.hairline + monthGap
        return ZStack(alignment: .topLeading) {
            if let month = bar.month {
                Text(month)
                    .font(Twin.Typeface.mono(9, bold: true))
                    .tracking(0.45)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
                    .frame(width: 0, alignment: .leading)
                    .offset(x: m.slotX(k), y: monthY)
            }
            Text(bar.day)
                .font(Twin.Typeface.mono(9, bold: bar.isLast))
                .foregroundStyle(bar.isLast ? Twin.Palette.ink : Twin.Palette.inkHint)
                .lineLimit(1)
                .fixedSize()
                .frame(width: m.slot)
                .offset(x: m.slotX(k), y: monthY + monthHeight + dayGap)
            // Tap anywhere in the night's column (bar, empty space above it, labels).
            Color.clear
                .frame(width: m.slot + gap, height: totalHeight - rowTops[0])
                .contentShape(Rectangle())
                .offset(x: m.slotX(k) - gap / 2, y: rowTops[0])
                .onTapGesture { select(bar.id) }
        }
        .accessibilityHidden(true)
    }

    private func select(_ id: Int) {
        guard selection != id else { return }
        withAnimation(Twin.Motion.spring) { selection = id }
    }
}
