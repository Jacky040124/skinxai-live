#if os(iOS)
import SwiftUI

/// One stacked timeline (Trends): every track shares the same night axis and scrolls sideways together.
///
/// - Top: minutes of scratching per night as bars (flare nights orange with an ink edge, the rest 15%
///   ink) and a dashed "your usual" line.
/// - Under it, thin line tracks (sleep, humidity, temperature, HRV…): a line with a light area, the
///   threshold dashed, and an orange dot with an ink edge on every out-of-range night.
/// - Then event lanes: a sticker with the event's emoji on its first night and a bar across the nights
///   it lasted (a new product in use, an exam week), or a small dot (a late workout). Tap one → `onEvent`.
/// - Month and day labels once at the bottom. A label gutter on the left names each track.
/// - Tap a night anywhere in its column: a cyan band highlights it across every track.
/// - More than `window` nights scroll sideways; the chart opens on the newest night (right edge). The
///   month of the first night on screen stays pinned at the left.
struct TimelineChart: View {
    struct Night: Identifiable, Equatable {
        var id: Int
        var minutes: Double
        var hot: Bool
        /// "20"
        var day: String
        /// "OCT"
        var month: String
        var startsMonth = false
        var isLast = false
        /// One value per track (nil: no data that night).
        var values: [Double?]
        var accessibility = ""
    }

    struct Track: Equatable {
        /// "Sleep"
        var name: String
        /// "h"
        var unit: String
        var domain: ClosedRange<Double>
        var threshold: Double
        /// Out of range under the threshold (dry air, short sleep, low HRV); otherwise at or above it.
        var flagBelow = true
        func flagged(_ v: Double) -> Bool { flagBelow ? v < threshold : v >= threshold }
    }

    struct Lane: Equatable {
        var name: String
        var unit: String
        /// Rows of events in the lane (events that start on the same night take one row each).
        var rows = 1
    }

    struct Event: Identifiable, Equatable {
        var id: String
        var lane: Int
        var row = 0
        /// First and last night.
        var start: Int
        var end: Int
        var emoji: String
        var fill: Color
        /// The bar across its nights.
        var span: Color
        /// A small dot instead of a sticker (late workouts).
        var dot = false
        var accessibility = ""
    }

    var nights: [Night]
    var tracks: [Track]
    var lanes: [Lane]
    var events: [Event]
    var usual: Double
    var scaleTop: Double
    @Binding var selection: Int
    /// Scrolls this night to the right edge when it changes.
    var focus: Int? = nil
    /// The most nights that share the width; with more, the chart scrolls.
    var window = 21
    var gap: CGFloat = 3
    var maxBar: CGFloat = 26
    var delay: Double = 0.2
    var onEvent: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var grown = false
    @State private var decorated = false
    @State private var spot: TimelineSpot?

    // MARK: Layout (top to bottom)

    static let gutter: CGFloat = 58
    /// Room on both sides of the plot so the selection band never clips.
    static let inset: CGFloat = 3
    private let plotTop: CGFloat = 8
    private let plotHeight: CGFloat = 112
    private let trackHeight: CGFloat = 24
    private let trackGap: CGFloat = 7
    private let rowHeight: CGFloat = 22
    private let laneGap: CGFloat = 6

    private var baseline: CGFloat { plotTop + plotHeight }
    private func trackTop(_ t: Int) -> CGFloat { baseline + 12 + CGFloat(t) * (trackHeight + trackGap) }
    private var tracksEnd: CGFloat { trackTop(tracks.count) - trackGap }
    private func laneTop(_ l: Int) -> CGFloat {
        tracksEnd + 10 + lanes.prefix(l).reduce(0) { $0 + CGFloat($1.rows) * rowHeight + laneGap }
    }
    private func rowMid(_ lane: Int, _ row: Int) -> CGFloat { laneTop(lane) + CGFloat(row) * rowHeight + rowHeight / 2 }
    private var lanesEnd: CGFloat { laneTop(lanes.count) - laneGap }
    private var monthY: CGFloat { lanesEnd + 8 }
    private var dayY: CGFloat { monthY + 12 }
    private var totalHeight: CGFloat { dayY + 13 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
                .frame(width: Self.gutter, height: totalHeight, alignment: .topLeading)
            GeometryReader { g in
                let m = Metrics(viewport: g.size.width - Self.inset * 2, count: nights.count, window: window, gap: gap, maxBar: maxBar)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        plot(m)
                            .frame(width: m.contentWidth, height: totalHeight, alignment: .topLeading)
                            .background(alignment: .bottomLeading) { anchors(m) }
                            .padding(.horizontal, Self.inset)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(!m.scrollable)
                    .defaultScrollAnchor(.trailing)
                    .modifier(TimelineSpotReader(step: m.slot + gap, count: nights.count, spot: $spot))
                    .mask { edgeFade(m) }
                    .overlay(alignment: .topLeading) { pinnedMonth(m).offset(x: Self.inset) }
                    .onChange(of: focus) { _, id in
                        guard m.scrollable, let id else { return }
                        withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo("n\(id)", anchor: .trailing) }
                    }
                    .onChange(of: selection) { _, id in
                        guard m.scrollable, let k = index(of: id) else { return }
                        let left = spot?.left ?? (nights.count - m.fit)
                        guard k < left || k >= left + m.fit else { return }
                        withAnimation(Twin.Motion.slide) { proxy.scrollTo("n\(id)", anchor: .center) }
                    }
                }
            }
            .frame(height: totalHeight)
        }
        .frame(height: totalHeight)
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true; decorated = true }
            } else {
                grown = true
                withAnimation(.easeInOut(duration: 0.8).delay(decorationDelay)) { decorated = true }
            }
        }
    }

    // MARK: Geometry

    private struct Metrics {
        let viewport: CGFloat
        let count: Int
        let window: Int
        let gap: CGFloat
        let maxBar: CGFloat
        var fit: Int { max(1, min(count, window)) }
        var slot: CGFloat { max(1, (viewport - gap * CGFloat(fit - 1)) / CGFloat(fit)) }
        var bar: CGFloat { min(slot, maxBar) }
        var scrollable: Bool { count > window }
        var contentWidth: CGFloat { scrollable ? CGFloat(count) * (slot + gap) - gap : viewport }
        func slotX(_ k: Int) -> CGFloat { CGFloat(k) * (slot + gap) }
        func center(_ k: Int) -> CGFloat { slotX(k) + slot / 2 }
    }

    private func index(of id: Int) -> Int? { nights.firstIndex { $0.id == id } }

    /// The first night that grows in: the first one on screen.
    private var entranceFirst: Int { max(0, nights.count - window) }
    private func beat(_ k: Int) -> Double { delay + Double(max(k - entranceFirst, 0)) * stagger }
    private var stagger: Double { nights.count - entranceFirst > 10 ? 0.025 : 0.05 }
    private var decorationDelay: Double { delay + Double(nights.count - entranceFirst) * stagger + 0.1 }

    private func barHeight(_ value: Double) -> CGFloat {
        let h = max(3, CGFloat(value / max(scaleTop, 0.001)) * plotHeight)
        return displayScale > 0 ? (h * displayScale).rounded() / displayScale : h
    }

    // MARK: Gutter

    private var gutter: some View {
        ZStack(alignment: .topLeading) {
            label("Scratch", "min / night").offset(y: plotTop)
            ForEach(Array(tracks.enumerated()), id: \.offset) { t, track in
                label(track.name, track.unit)
                    .frame(height: trackHeight, alignment: .center)
                    .offset(y: trackTop(t))
            }
            ForEach(Array(lanes.enumerated()), id: \.offset) { l, lane in
                label(lane.name, lane.unit)
                    .frame(height: CGFloat(lane.rows) * rowHeight, alignment: .center)
                    .offset(y: laneTop(l))
            }
        }
        .opacity(grown ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(delay), value: grown)
        .accessibilityHidden(true)
    }

    private func label(_ name: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(Twin.Typeface.sans(12, .bold))
                .foregroundStyle(Twin.Palette.ink)
            Text(unit.uppercased())
                .font(Twin.Typeface.mono(8, bold: true))
                .tracking(0.3)
                .foregroundStyle(Twin.Palette.inkHint)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: Self.gutter - 6, alignment: .leading)
    }

    // MARK: Plot

    private func plot(_ m: Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            band(m)
            // Lane separators: a hairline under the bars and between the tracks.
            Rectangle().fill(Twin.Palette.hairline)
                .frame(width: m.contentWidth, height: Twin.Stroke.hairline)
                .offset(y: baseline)
            ForEach(Array(nights.enumerated()), id: \.element.id) { k, night in
                bar(night, k: k, m: m)
            }
            usualLine(m)
            ForEach(tracks.indices, id: \.self) { t in track(t, m: m) }
            ForEach(lanes.indices, id: \.self) { l in
                Rectangle().fill(Twin.Palette.hairline.opacity(0.6))
                    .frame(width: m.contentWidth, height: Twin.Stroke.hairline)
                    .offset(y: laneTop(l) - 5)
            }
            ForEach(Array(nights.enumerated()), id: \.element.id) { k, night in
                labelsAndTap(night, k: k, m: m)
            }
            ForEach(events) { event in eventView(event, m: m) }
        }
    }

    /// The selected night: a cyan band through every track.
    @ViewBuilder private func band(_ m: Metrics) -> some View {
        if let k = index(of: selection) {
            let w = m.slot + gap + 2
            RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                .fill(Twin.Palette.cyanSoft)
                .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                    .strokeBorder(Twin.Palette.cyan, lineWidth: Twin.Stroke.ink))
                .frame(width: w, height: totalHeight - 2)
                .offset(x: m.center(k) - w / 2, y: 1)
                .opacity(grown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(delay), value: grown)
                .allowsHitTesting(false)
        }
    }

    private func bar(_ night: Night, k: Int, m: Metrics) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
        return Group {
            if night.hot {
                shape.fill(Twin.Palette.orange).overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: 1))
            } else {
                shape.fill(Twin.Palette.ink.opacity(0.15))
            }
        }
        .frame(width: m.bar, height: barHeight(night.minutes))
        .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
        .opacity(grown ? 1 : 0)
        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(beat(k)), value: grown)
        .frame(width: m.slot, height: plotHeight, alignment: .bottom)
        .offset(x: m.slotX(k), y: plotTop)
        .allowsHitTesting(false)
    }

    private func usualLine(_ m: Metrics) -> some View {
        ChartHLine()
            .trim(from: 0, to: decorated ? 1 : 0)
            .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: m.contentWidth, height: 2)
            .offset(y: baseline - barHeight(usual) - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Tracks

    private func level(_ v: Double, _ t: Int) -> CGFloat {
        let d = tracks[t].domain
        return CGFloat(min(max((v - d.lowerBound) / (d.upperBound - d.lowerBound), 0), 1))
    }

    private func pointY(_ v: Double, _ t: Int) -> CGFloat { trackTop(t) + 3 + (1 - level(v, t)) * (trackHeight - 6) }

    private func track(_ t: Int, m: Metrics) -> some View {
        let spec = tracks[t]
        let points: [CGPoint?] = nights.indices.map { k in
            nights[k].values[safe: t].flatMap { $0 }.map { CGPoint(x: m.center(k), y: pointY($0, t)) }
        }
        let reveal = nights.count > 1 ? Double(entranceFirst) / Double(nights.count - 1) : 0
        let selected = index(of: selection).flatMap { k in nights[k].values[safe: t].flatMap { $0 }.map { (k, $0) } }
        return ZStack(alignment: .topLeading) {
            ChartHLine()
                .stroke(Twin.Palette.seam.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: m.contentWidth, height: 1)
                .offset(y: pointY(spec.threshold, t))
            TimelineArea(points: points, bottom: trackTop(t) + trackHeight)
                .fill(Twin.Palette.ink.opacity(0.05))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: m.contentWidth * (decorated || reduceMotion ? 1 : reveal))
                }
            TimelineLine(points: points)
                .trim(from: 0, to: decorated || reduceMotion ? 1 : reveal)
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            ForEach(Array(nights.enumerated()), id: \.element.id) { k, night in
                if let v = night.values[safe: t].flatMap({ $0 }), spec.flagged(v) {
                    Circle()
                        .fill(Twin.Palette.orange)
                        .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .scaleEffect(decorated || reduceMotion ? 1 : 0.01)
                        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(decorationDelay + 0.4), value: decorated)
                        .offset(x: m.center(k) - 3.5, y: pointY(v, t) - 3.5)
                }
            }
            if let selected {
                Circle()
                    .fill(Twin.Palette.cyan)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .offset(x: m.center(selected.0) - 4.5, y: pointY(selected.1, t) - 4.5)
                    .opacity(decorated ? 1 : 0)
            }
        }
        .frame(width: m.contentWidth, height: totalHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Events

    private func eventView(_ event: Event, m: Metrics) -> some View {
        let a = index(of: event.start) ?? 0
        let b = index(of: event.end) ?? a
        let y = rowMid(event.lane, event.row)
        let size: CGFloat = 19
        let d = decorationDelay + 0.15 + Double(event.lane) * 0.1
        return ZStack(alignment: .topLeading) {
            if b > a {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(event.span)
                    .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: m.center(b) - m.center(a) + 4, height: 6)
                    .scaleEffect(x: decorated || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(d + 0.15), value: decorated)
                    .offset(x: m.center(a) - 2, y: y - 3)
                    .allowsHitTesting(false)
            }
            Button { onEvent(event.id) } label: {
                Group {
                    if event.dot {
                        Circle().fill(Twin.Palette.ink.opacity(0.55)).frame(width: 6, height: 6)
                            .frame(width: m.slot + gap, height: rowHeight)
                    } else {
                        Text(event.emoji)
                            .font(.system(size: 11))
                            .frame(width: size, height: size)
                            .sticker(event.fill)
                    }
                }
                .contentShape(Rectangle().inset(by: -3))
            }
            .buttonStyle(PressableStyle())
            .scaleEffect(decorated || reduceMotion ? 1 : 0.5)
            .opacity(decorated ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(d), value: decorated)
            .frame(width: 0, height: 0)
            .offset(x: m.center(a), y: y)
            .accessibilityLabel(event.accessibility)
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Labels and taps

    /// Day numbers: every night when there's room, otherwise every other one (counting back from last
    /// night, which is always labeled, in bold).
    /// The selected night is always labeled (its neighbors give way).
    private func showsDay(_ k: Int, m: Metrics) -> Bool {
        if m.slot + gap >= 20 { return true }
        if let s = index(of: selection) {
            if k == s { return true }
            if abs(k - s) == 1 { return false }
        }
        return (nights.count - 1 - k) % 2 == 0
    }

    private func labelsAndTap(_ night: Night, k: Int, m: Metrics) -> some View {
        let left = spot?.left ?? max(0, nights.count - m.fit)
        return ZStack(alignment: .topLeading) {
            if night.startsMonth && k > left {
                Text(night.month)
                    .font(Twin.Typeface.mono(9, bold: true))
                    .tracking(0.45)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
                    .frame(width: 0, alignment: .leading)
                    .offset(x: m.slotX(k), y: monthY)
            }
            if showsDay(k, m: m) {
                Text(night.day)
                    .font(Twin.Typeface.mono(9, bold: night.isLast || night.id == selection))
                    .foregroundStyle(night.isLast || night.id == selection ? Twin.Palette.ink : Twin.Palette.inkHint)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: m.slot + gap)
                    .offset(x: m.slotX(k) - gap / 2, y: dayY)
            }
            Color.clear
                .frame(width: m.slot + gap, height: totalHeight)
                .contentShape(Rectangle())
                .offset(x: m.slotX(k) - gap / 2)
                .onTapGesture { select(night.id) }
                .accessibilityElement()
                .accessibilityLabel(night.accessibility)
                .accessibilityAddTraits(selection == night.id ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(night.id) }
        }
    }

    /// The month of the first night on screen, pinned at the left ("‹ OCT" while older nights hide there).
    private func pinnedMonth(_ m: Metrics) -> some View {
        let left = m.scrollable ? min(max(spot?.left ?? (nights.count - m.fit), 0), max(nights.count - 1, 0)) : 0
        let soon = (left + 1...left + 2).contains { nights.indices.contains($0) && nights[$0].startsMonth }
        let more = m.scrollable && left > 0
        let month = nights.indices.contains(left) ? nights[left].month : ""
        return Text(soon ? (more ? "‹" : "") : (more ? "‹ \(month)" : month))
            .font(Twin.Typeface.mono(9, bold: true))
            .tracking(0.45)
            .foregroundStyle(Twin.Palette.inkHint)
            .fixedSize()
            .padding(.trailing, 4)
            .background(Twin.Palette.paper)
            .offset(y: monthY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Scrolling

    private func anchors(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            ForEach(nights) { night in
                Color.clear.frame(width: m.slot, height: 1).id("n\(night.id)").padding(.trailing, gap)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func edgeFade(_ m: Metrics) -> some View {
        let fadeLeft = m.scrollable && spot?.atStart != true
        let fadeRight = m.scrollable && spot?.atEnd == false
        return HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(fadeLeft ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(fadeRight ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
        }
        .animation(.easeOut(duration: 0.25), value: fadeLeft)
        .animation(.easeOut(duration: 0.25), value: fadeRight)
    }

    private func select(_ id: Int) {
        guard selection != id else { return }
        withAnimation(Twin.Motion.spring) { selection = id }
    }
}

// MARK: - Helpers

private struct TimelineSpot: Equatable {
    var left: Int
    var atStart: Bool
    var atEnd: Bool
}

private struct TimelineSpotReader: ViewModifier {
    let step: CGFloat
    let count: Int
    @Binding var spot: TimelineSpot?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: TimelineSpot.self) { geo in
                let x = geo.contentOffset.x + geo.contentInsets.leading
                let maxX = geo.contentSize.width - geo.containerSize.width
                let left = Int(((x - 2) / max(step, 1)).rounded(.up))
                return TimelineSpot(left: min(max(left, 0), max(count - 1, 0)), atStart: x <= 1, atEnd: x >= maxX - 1)
            } action: { _, new in
                spot = new
            }
        } else {
            content
        }
    }
}

/// A line through the points (a gap where a night has no value).
private struct TimelineLine: Shape {
    var points: [CGPoint?]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var open = false
        for point in points {
            guard let point else { open = false; continue }
            if open { p.addLine(to: point) } else { p.move(to: point); open = true }
        }
        return p
    }
}

/// The light area under a track's line, down to the track's bottom.
private struct TimelineArea: Shape {
    var points: [CGPoint?]
    var bottom: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var run: [CGPoint] = []
        func flush() {
            guard let first = run.first, let last = run.last, run.count > 1 else { run = []; return }
            p.move(to: CGPoint(x: first.x, y: bottom))
            run.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: bottom))
            p.closeSubpath()
            run = []
        }
        for point in points {
            if let point { run.append(point) } else { flush() }
        }
        flush()
        return p
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
#endif
