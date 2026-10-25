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
/// - Under those, the weather on the same timeline: two thin line tracks, humidity and the day's high,
///   one point per night at its bar's center. Dry days (and hot days) get an orange dot with an ink edge,
///   a dashed line marks where "dry" (and "hot") begins, and the selected night gets a cyan dot on both
///   tracks, its values in the track titles. The lines draw in left to right after the bars.
/// - Tap a night to select it: a cyan outline moves to its bar (matchedGeometryEffect) with a
///   selection haptic.
/// - A shorter range zooms in: the nights before the range slide out to the left and fade while the
///   others widen (and slide back in when the range grows again).
/// - More than `window` nights scroll sideways: bars keep the width they have at `window` nights, the
///   newest night sits at the right and the chart opens scrolled to it. The left edge fades and the
///   month label gets a "‹" while older nights hide there. A scrolling chart runs out to the card's
///   edges (`sidePad` = the card padding).
struct NightsChart: View {
    struct Bar: Identifiable, Equatable {
        /// The night.
        var id: Int
        var value: Double
        var hot: Bool
        /// Day number under the bar, e.g. "20".
        var day: String
        /// Its month, e.g. "OCT".
        var month: String
        /// The 1st of a month: its month label sits over its day number.
        var startsMonth = false
        var isLast = false
        /// Humidity that day, percent (nil on every bar: no weather tracks).
        var humidity: Int? = nil
        /// A dry day (an orange dot on the humidity track).
        var dry = false
        /// The day's high, °F.
        var highF: Int? = nil
        /// A hot day (an orange dot on the temperature track).
        var hotDay = false
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
        /// The sticker starts at the stem instead of being centered on it.
        var leading = false
    }

    /// A weather track's scale and its threshold line ("dry" under 35%, "hot" from 85 °F).
    struct Track: Equatable {
        var domain: ClosedRange<Double>
        var threshold: Double
        /// "DRY UNDER 35%"
        var key: String
    }

    var bars: [Bar]
    /// How many of the last nights are on the chart (7, or all of them).
    var shown: Int
    /// The most nights that share the width; with more, the chart scrolls.
    var window = 14
    var usual: Double
    /// Minutes at the top of the plot.
    var scaleTop: Double
    var markers: [Marker] = []
    @Binding var selection: Int
    /// Scrolls this night to the right edge when it changes (a scrolling chart).
    var focus: Int? = nil
    var plotHeight: CGFloat = 170
    /// Room above the plot for the two marker rows.
    var markerBand: CGFloat = 64
    var gap: CGFloat = 4
    /// Bars never get wider than this (a short range); they stay centered in their slot.
    var maxBarWidth: CGFloat = 34
    /// The humidity and temperature tracks' scales.
    var humidityTrack = Track(domain: 20...80, threshold: 35, key: "DRY UNDER 35%")
    var temperatureTrack = Track(domain: 55...95, threshold: 85, key: "HOT 85°F+")
    /// The card's padding: a scrolling chart runs out to the card's edges.
    var sidePad: CGFloat = Twin.Space.l
    var delay: Double = 0.12
    var stagger: Double = 0.04

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var grown = false
    @State private var decorated = false
    /// Where a scrolling chart is (nil until it has scrolled: it opens at the right end).
    @State private var spot: Spot?

    /// Top of each marker row, from the top of the chart (the prototype's -56 and -30 above the plot).
    private var rowTops: [CGFloat] { [markerBand - 56, markerBand - 30] }
    private let flagHeight: CGFloat = 18
    private let monthGap: CGFloat = 6, monthHeight: CGFloat = 11, dayGap: CGFloat = 2, dayHeight: CGFloat = 12
    private let weatherGap: CGFloat = 16, trackTitleHeight: CGFloat = 11, trackTitleGap: CGFloat = 5
    private let trackHeight: CGFloat = 24, trackGap: CGFloat = 12

    private var hasWeather: Bool { bars.contains { $0.humidity != nil } }
    private var plotBottom: CGFloat { markerBand + plotHeight }
    private var monthY: CGFloat { plotBottom + Twin.Stroke.hairline + monthGap }
    private var dayY: CGFloat { monthY + monthHeight + dayGap }
    /// Top of track `t`'s title (0 = humidity, 1 = temperature), and of its line.
    private func trackTitleY(_ t: Int) -> CGFloat {
        dayY + dayHeight + weatherGap + CGFloat(t) * (trackTitleHeight + trackTitleGap + trackHeight + trackGap)
    }
    private func trackY(_ t: Int) -> CGFloat { trackTitleY(t) + trackTitleHeight + trackTitleGap }
    private var totalHeight: CGFloat { hasWeather ? trackY(1) + trackHeight + 4 : dayY + dayHeight }
    private var first: Int { min(max(bars.count - shown, 0), max(bars.count - 1, 0)) }

    var body: some View {
        GeometryReader { g in
            let m = Metrics(viewport: g.size.width, count: bars.count, first: first, window: window, gap: gap, maxBar: maxBarWidth)
            let left = leftBar(m)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Twin.Palette.hairline)
                            .frame(width: m.contentWidth - m.lineStart, height: Twin.Stroke.hairline)
                            .offset(x: m.lineStart, y: plotBottom)
                        ForEach(Array(bars.enumerated()), id: \.element.id) { k, bar in
                            column(bar, k: k, m: m)
                        }
                        usualLine(m)
                        ForEach(markers) { marker in stem(marker, m: m) }
                        ForEach(Array(bars.enumerated()), id: \.element.id) { k, bar in
                            labels(bar, k: k, m: m, left: left)
                        }
                        if hasWeather {
                            weatherTrack(0, m: m)
                            weatherTrack(1, m: m)
                        }
                        // Flags last: they take their own taps above the columns' tap areas.
                        ForEach(markers) { marker in flag(marker, m: m) }
                    }
                    .frame(width: m.contentWidth, height: totalHeight, alignment: .topLeading)
                    .padding(.horizontal, sidePad)
                    .background(alignment: .bottomTrailing) { scrollAnchors(m) }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(!m.scrollable)
                .defaultScrollAnchor(.trailing)
                .modifier(ScrollSpotReader(slot: m.slotAll + gap, count: bars.count, spot: $spot))
                .frame(width: g.size.width + sidePad * 2, height: totalHeight)
                .mask { edgeFade(m) }
                .overlay(alignment: .topLeading) { pinnedLabels(m, left: left).offset(x: sidePad) }
                .offset(x: -sidePad)
                .onChange(of: shown) { _, _ in
                    // Back to the newest night when the chart stops scrolling (7 nights).
                    guard !m.scrollable else { return }
                    withAnimation(Twin.Motion.spring) { proxy.scrollTo("end", anchor: .trailing) }
                }
                .onChange(of: selection) { _, id in
                    // A night picked elsewhere ("What changed") scrolls into view.
                    guard m.scrollable, let k = index(of: id), k < left || k >= left + m.fitAll else { return }
                    withAnimation(Twin.Motion.slide) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: focus) { _, id in
                    guard m.scrollable, let id else { return }
                    withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(id, anchor: .trailing) }
                }
            }
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

    /// The first night that grows in: the first one on screen.
    private var entranceFirst: Int { max(first, bars.count - window) }

    /// The usual line draws once every bar on screen has grown.
    private var decorationDelay: Double { delay + Double(bars.count - entranceFirst) * stagger + 0.2 }

    /// Entrance beat of bar `k`: the first night on screen grows first (the ones scrolled out of view
    /// to the left are simply there).
    private func beat(_ k: Int) -> Double { delay + Double(max(k - entranceFirst, 0)) * stagger }

    /// A marker drops in right after its own bar has grown.
    private func markerDelay(_ marker: Marker) -> Double { beat(index(of: marker.bar) ?? 0) + 0.45 }

    // MARK: Geometry

    private struct Metrics {
        /// The card's content width.
        let viewport: CGFloat
        /// All nights.
        let count: Int
        /// The first night on the chart.
        let first: Int
        let window: Int
        let gap: CGFloat
        let maxBar: CGFloat

        /// Nights sharing the width now, and with every night on the chart.
        var fit: Int { max(1, min(count - first, window)) }
        var fitAll: Int { max(1, min(count, window)) }
        private func slot(_ n: Int) -> CGFloat { max(1, (viewport - gap * CGFloat(n - 1)) / CGFloat(n)) }
        var slot: CGFloat { slot(fit) }
        var slotAll: CGFloat { slot(fitAll) }
        var bar: CGFloat { min(slot, maxBar) }
        /// Every night on the chart doesn't fit: it scrolls.
        var scrollable: Bool { count - first > window }
        /// Width of the plot: the viewport, or every night at its all-time width when that is wider.
        /// It stays the same across ranges, so zooming never makes the scroll position jump.
        var contentWidth: CGFloat {
            count > window ? CGFloat(count) * (slotAll + gap) - gap : viewport
        }
        /// Left edge of bar `k`'s slot. The newest night ends at the right edge; nights before the
        /// range sit left of the visible part.
        func slotX(_ k: Int) -> CGFloat { contentWidth - CGFloat(count - k) * (slot + gap) + gap }
        func center(_ k: Int) -> CGFloat { slotX(k) + slot / 2 }
        /// Where the baseline and the usual line start (the first night on the chart).
        var lineStart: CGFloat { max(0, slotX(first)) }
    }

    /// The first night at the left edge.
    private func leftBar(_ m: Metrics) -> Int {
        guard m.scrollable else { return first }
        return min(max(spot?.left ?? (bars.count - m.fitAll), 0), max(bars.count - 1, 0))
    }

    /// Bar height for `value`, on whole pixels: a bar whose top sits on a half pixel would end a pixel
    /// lower than the others once SwiftUI rounds its frame, darkening the baseline under it.
    private func height(_ value: Double) -> CGFloat {
        let h = max(3, CGFloat(value / max(scaleTop, 0.001)) * plotHeight)
        return displayScale > 0 ? (h * displayScale).rounded() / displayScale : h
    }

    private func index(of id: Int) -> Int? { bars.firstIndex { $0.id == id } }
    private func isVisible(_ k: Int) -> Bool { k >= first && k < bars.count }

    // MARK: Bars

    private func column(_ bar: Bar, k: Int, m: Metrics) -> some View {
        let h = height(bar.value)
        let selected = selection == bar.id
        let visible = isVisible(k)
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
        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(beat(k)), value: grown)
        .frame(width: m.slot, height: plotHeight, alignment: .bottom)
        .offset(x: m.slotX(k), y: markerBand)
        .opacity(visible ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibility)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(bar.id) }
        .accessibilityHidden(!visible)
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
            .frame(width: m.contentWidth - m.lineStart, height: 2)
            .offset(x: m.lineStart, y: plotBottom - height(usual) - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Weather tracks

    private func trackSpec(_ t: Int) -> Track { t == 0 ? humidityTrack : temperatureTrack }
    private func trackValue(_ bar: Bar, _ t: Int) -> Int? { t == 0 ? bar.humidity : bar.highF }
    private func trackFlag(_ bar: Bar, _ t: Int) -> Bool { t == 0 ? bar.dry : bar.hotDay }

    /// 0 (bottom) … 1 (top) on track `t`'s scale.
    private func level(_ value: Double, _ t: Int) -> CGFloat {
        let d = trackSpec(t).domain
        return CGFloat(min(max((value - d.lowerBound) / (d.upperBound - d.lowerBound), 0), 1))
    }

    /// Height of a point on a track: the line keeps 3 pt from the edges, so dots never clip.
    private func trackPointY(_ value: Double, _ t: Int) -> CGFloat {
        trackY(t) + 3 + (1 - level(value, t)) * (trackHeight - 6)
    }

    /// One thin line through every night's value at its bar's center (the line moves with the bars
    /// when the range changes), the threshold dashed, dots on dry / hot days, and the selected night.
    private func weatherTrack(_ t: Int, m: Metrics) -> some View {
        let spec = trackSpec(t)
        let values = bars.map { trackValue($0, t).map { Double(level(Double($0), t)) } ?? 0.5 }
        let step = m.slot + gap
        let origin = m.contentWidth - CGFloat(bars.count) * step + gap + m.slot / 2
        // The line starts at the first night on the chart (the ones before it slide out to the left).
        let start = first > 0 ? max(0, m.center(first) - 2) : 0
        let reveal = bars.count > 1 ? Double(entranceFirst) / Double(bars.count - 1) : 0
        let selected = index(of: selection).flatMap { k in trackValue(bars[k], t).map { (k, $0) } }
        return ZStack(alignment: .topLeading) {
            ChartHLine()
                .stroke(Twin.Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: m.contentWidth - start, height: 1)
                .offset(x: start, y: trackPointY(spec.threshold, t))
            TrackLine(values: values, origin: origin, step: step)
                .trim(from: 0, to: decorated || reduceMotion ? 1 : reveal)
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: m.contentWidth, height: trackHeight - 6)
                .offset(y: trackY(t) + 3)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: max(0, m.contentWidth - start), height: totalHeight).offset(x: start)
                }
            ForEach(Array(bars.enumerated()), id: \.element.id) { k, bar in
                if trackFlag(bar, t), let v = trackValue(bar, t) {
                    Circle()
                        .fill(Twin.Palette.orange)
                        .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .scaleEffect(decorated || reduceMotion ? 1 : 0.01)
                        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(decorationDelay + 0.5), value: decorated)
                        .offset(x: m.center(k) - 3.5, y: trackPointY(Double(v), t) - 3.5)
                        .opacity(isVisible(k) ? 1 : 0)
                }
            }
            if let selected {
                Circle()
                    .fill(Twin.Palette.cyan)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .offset(x: m.center(selected.0) - 4.5, y: trackPointY(Double(selected.1), t) - 4.5)
                    .opacity(decorated ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: decorated)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // each bar's own label says the weather
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(markerDelay(marker) + 0.1), value: decorated)
            .offset(x: m.center(k) - 1, y: top)
            .opacity(isVisible(k) ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func flag(_ marker: Marker, m: Metrics) -> some View {
        let k = index(of: marker.bar) ?? 0
        let x = marker.trailing ? m.center(k) + 6 : (marker.leading ? m.center(k) - 6 : m.center(k))
        let visible = isVisible(k)
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
        .frame(width: 0, alignment: marker.trailing ? .trailing : (marker.leading ? .leading : .center))
        .offset(x: x, y: rowTops[min(max(marker.row, 0), rowTops.count - 1)])
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(true)   // each bar's own label names its marker
    }

    // MARK: Labels and taps

    /// Labels that stay at the left edge while the chart scrolls: the month of the first night on
    /// screen ("‹ OCT" while older nights hide to the left; left out when a new month begins right
    /// after it: that month's own label shows), and the weather tracks' titles.
    private func pinnedLabels(_ m: Metrics, left: Int) -> some View {
        let soon = (left + 1...left + 2).contains { bars.indices.contains($0) && bars[$0].startsMonth }
        let more = m.scrollable && left > 0
        let month = bars.indices.contains(left) ? bars[left].month : ""
        return ZStack(alignment: .topLeading) {
            Text(soon ? (more ? "‹" : "") : (more ? "‹ \(month)" : month))
                .font(Twin.Typeface.mono(9, bold: true))
                .tracking(0.45)
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize()
                .offset(y: monthY)
            if hasWeather {
                ForEach(0..<2, id: \.self) { t in
                    trackTitle(t, m: m)
                        .offset(y: trackTitleY(t))
                }
            }
        }
        .frame(width: m.viewport, height: totalHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "HUMIDITY 29%" (the selected night's value) on the left, "- - DRY UNDER 35%" on the right.
    private func trackTitle(_ t: Int, m: Metrics) -> some View {
        let value = index(of: selection).flatMap { trackValue(bars[$0], t) }
        return HStack(spacing: 5) {
            Text(t == 0 ? "HUMIDITY" : "HIGH")
            if let value {
                Text(t == 0 ? "\(value)%" : "\(value)°F")
                    .foregroundStyle(Twin.Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
            }
            Spacer(minLength: 8)
            ChartHLine()
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 14, height: 1)
            Text(trackSpec(t).key)
        }
        .font(Twin.Typeface.mono(9, bold: true))
        .tracking(0.45)
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .frame(width: m.viewport, height: trackTitleHeight)
        .opacity(grown ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(delay + 0.3), value: grown)
    }

    /// The day under a bar (and its month on the 1st of a month), and the night's tap area (its column).
    private func labels(_ bar: Bar, k: Int, m: Metrics, left: Int) -> some View {
        let visible = isVisible(k)
        return ZStack(alignment: .topLeading) {
            if bar.startsMonth && k > left {
                Text(bar.month)
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
                .offset(x: m.slotX(k), y: dayY)
            // Tap anywhere in the night's column (bar, empty space above it, labels, weather).
            Color.clear
                .frame(width: m.slot + gap, height: totalHeight - rowTops[0])
                .contentShape(Rectangle())
                .offset(x: m.slotX(k) - gap / 2, y: rowTops[0])
                .onTapGesture { select(bar.id) }
                .allowsHitTesting(visible)
        }
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: Scrolling

    /// Invisible slots laid out like the all-time bars (the bars themselves are placed with offsets),
    /// so `scrollTo` can find a night; "end" is the right padding.
    private func scrollAnchors(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            ForEach(bars) { bar in
                Color.clear.frame(width: m.slotAll, height: 1).id(bar.id)
                    .padding(.trailing, gap)
            }
            Color.clear.frame(width: max(sidePad - gap, 1), height: 1).id("end")
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Older (or newer) nights hiding past an edge fade out into it.
    private func edgeFade(_ m: Metrics) -> some View {
        let fadeLeft = m.scrollable && (spot?.atStart == false || (spot == nil && bars.count > m.fitAll))
        let fadeRight = m.scrollable && spot?.atEnd == false
        return HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(fadeLeft ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: sidePad + 18)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(fadeRight ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: sidePad + 18)
        }
        .animation(.easeOut(duration: 0.25), value: fadeLeft)
        .animation(.easeOut(duration: 0.25), value: fadeRight)
    }

    private func select(_ id: Int) {
        guard selection != id else { return }
        withAnimation(Twin.Motion.spring) { selection = id }
    }
}

/// Where a scrolling `NightsChart` is: the night at its left edge, and whether it is at either end.
private struct Spot: Equatable {
    var left: Int
    var atStart: Bool
    var atEnd: Bool
}

/// Follows the scroll position (iOS 18+; before that the chart keeps its opening state: at the right
/// end). Only changes of `Spot` reach the view, not every scrolled point.
private struct ScrollSpotReader: ViewModifier {
    let slot: CGFloat
    let count: Int
    @Binding var spot: Spot?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, watchOS 11.0, *) {
            content.onScrollGeometryChange(for: Spot.self) { geo in
                let x = geo.contentOffset.x + geo.contentInsets.leading
                let maxX = geo.contentSize.width - geo.containerSize.width
                let left = Int(((x - 2) / max(slot, 1)).rounded(.up))
                return Spot(left: min(max(left, 0), max(count - 1, 0)), atStart: x <= 1, atEnd: x >= maxX - 1)
            } action: { _, new in
                spot = new
            }
        } else {
            content
        }
    }
}

/// A weather track's line: one point per night, `origin + k × step` across (animatable, so the line
/// follows the bars when the range changes), `values` (0 … 1, 1 = top) up.
private struct TrackLine: Shape {
    var values: [Double]
    var origin: CGFloat
    var step: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(origin, step) }
        set { origin = newValue.first; step = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (k, v) in values.enumerated() {
            let point = CGPoint(x: origin + CGFloat(k) * step, y: rect.minY + CGFloat(1 - v) * rect.height)
            if k == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}
