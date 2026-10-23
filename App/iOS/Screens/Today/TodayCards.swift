import SwiftUI
import EczemaKit

// MARK: - Call to action (Claude / the running test)

/// Pink-soft card with an ink edge and a shimmer sweep (SPEC §4 "Claude call-to-action").
/// The shimmer sweeps a few times after the card appears (it is news waiting to be read),
/// and the icon tile turns a notch with each sweep. Reduce Motion: no sweep.
struct TodayActionCard<Accessory: View>: View {
    enum Icon { case glyph(String), symbol(String) }

    var icon: Icon
    var title: String
    var subtitle: String
    var fill: Color
    var tile: Color
    var shimmer: Bool
    var action: () -> Void
    var accessory: () -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -1.4
    @State private var sweeps = 0

    init(glyph: String, title: String, subtitle: String, fill: Color = Twin.Palette.pinkSoft,
         tile: Color = Twin.Palette.pink, shimmer: Bool = true, action: @escaping () -> Void,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(icon: .glyph(glyph), title: title, subtitle: subtitle, fill: fill, tile: tile,
                  shimmer: shimmer, action: action, accessory: accessory)
    }

    init(symbol: String, title: String, subtitle: String, fill: Color = Twin.Palette.pinkSoft,
         tile: Color = Twin.Palette.pink, shimmer: Bool = true, action: @escaping () -> Void,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(icon: .symbol(symbol), title: title, subtitle: subtitle, fill: fill, tile: tile,
                  shimmer: shimmer, action: action, accessory: accessory)
    }

    private init(icon: Icon, title: String, subtitle: String, fill: Color, tile: Color, shimmer: Bool,
                 action: @escaping () -> Void, accessory: @escaping () -> Accessory) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.fill = fill; self.tile = tile
        self.shimmer = shimmer; self.action = action; self.accessory = accessory
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 13) {
                iconTile
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Twin.Typeface.sans(16, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text(subtitle)
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    accessory()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .offset(x: sweeps % 2 == 1 ? 3 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background }
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .contentShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .task(id: shimmer) { await runShimmer() }
    }

    private var iconTile: some View {
        Group {
            switch icon {
            case .glyph(let g):
                Text(g).font(.system(size: 19, weight: .bold))
                    .rotationEffect(.degrees(Double(sweeps) * 60))
            case .symbol(let s):
                Image(systemName: s).font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: sweeps)
            }
        }
        .foregroundStyle(Twin.Palette.ink)
        .frame(width: 36, height: 36)
        .sticker(tile)
        .accessibilityHidden(true)
    }

    private var background: some View {
        ZStack {
            fill
            if shimmer {
                GeometryReader { g in
                    LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.2),
                                           .init(color: .white.opacity(0.85), location: 0.5),
                                           .init(color: .white.opacity(0), location: 0.8)],
                                   startPoint: UnitPoint(x: 0, y: 0.3), endPoint: UnitPoint(x: 1, y: 0.7))
                        .frame(width: g.size.width * 0.8)
                        .offset(x: sweep * g.size.width)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
    }

    private func runShimmer() async {
        guard shimmer, !reduceMotion else { return }
        try? await Task.sleep(for: .seconds(1.1))
        for _ in 0..<3 {
            if Task.isCancelled { return }
            sweep = -1.4
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 1.5)) { sweep = 1.4 }
            withAnimation(Twin.Motion.bouncy) { sweeps += 1 }
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(Twin.Motion.bouncy) { sweeps += 1 }
            try? await Task.sleep(for: .seconds(2.6))
        }
    }
}

/// The 10 day tiles of the running test (done = lime, today = yellow and bobbing, future = paper).
struct TodayTestTiles: View {
    let day: Int
    let length: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(length, 1), id: \.self) { d in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(d < day ? Twin.Palette.lime : (d == day ? Twin.Palette.yellow : Twin.Palette.paper))
                    .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .offset(y: d == day && bob ? -2.5 : 0)
            }
        }
        .padding(.top, 7)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.9)) { bob = true }
        }
        .accessibilityLabel("Day \(day) of \(length)")
    }
}

// MARK: - Sleep / Stress mini cards

struct TodayMetricCard: View {
    let title: String
    let value: Double
    let decimals: Int
    let unit: String
    let note: String
    /// true = worse than usual (orange), false = fine (lime), nil = no comparison.
    let worse: Bool?
    /// Last 7 days, today last.
    let history: [Double]
    /// The usual value (dashed line across the spark bars).
    var usual: Double? = nil
    var delay: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                CountUp(value: value, decimals: decimals, font: Twin.Typeface.sans(30, .bold), delay: delay)
                    .tracking(-1)
                Text(unit).font(Twin.Typeface.sans(15)).foregroundStyle(Twin.Palette.inkHint)
                Spacer(minLength: 6)
                SparkBars(values: history, highlight: worse == true ? Twin.Palette.orange : Twin.Palette.ink,
                          usual: usual, delay: delay + 0.25)
                    .frame(width: 44, height: 22)
            }
            HStack(spacing: 6) {
                if let worse {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(worse ? Twin.Palette.orange : Twin.Palette.lime)
                        .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                        .frame(width: 8, height: 8)
                }
                Text(note)
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Around you · auto

struct TodayAroundYouCard: View {
    let day: DayRecord
    let auto: [Exposure]

    private struct Item: Identifiable { let id: String; let emoji: String; let text: String; let fill: Color }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Around you · auto")
            StickerWrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    TodayEmojiSticker(emoji: item.emoji, text: item.text, fill: item.fill)
                        .modifier(TodayPopIn(delay: 0.5 + Double(i) * 0.07))
                }
            }
        }
        .twinCard(fill: Twin.Palette.cream)
    }

    private var items: [Item] {
        var out: [Item] = []
        let h = Int(day.humidityPct.rounded())
        let dry = day.humidityPct < 35
        let humid = day.humidityPct > 70
        out.append(Item(id: "humidity", emoji: "💧",
                        text: dry ? "Humidity \(h)% · dry" : (humid ? "Humidity \(h)% · humid" : "Humidity \(h)%"),
                        fill: dry ? Twin.Palette.orange : Twin.Palette.paper))
        let aqi = day.aqi
        let word = aqi <= 50 ? "good" : (aqi <= 100 ? "moderate" : (aqi <= 150 ? "poor" : "unhealthy"))
        out.append(Item(id: "aqi", emoji: "🍃", text: "Air quality \(aqi) · \(word)",
                        fill: aqi > 100 ? Twin.Palette.orange : Twin.Palette.paper))
        if day.pollen != .unknown {
            out.append(Item(id: "pollen", emoji: "🌼", text: "Pollen · \(day.pollen.label.lowercased())",
                            fill: day.pollen == .high ? Twin.Palette.orange : Twin.Palette.paper))
        }
        out.append(Item(id: "temp", emoji: "🌡️", text: TodayTrends.Format.temperature(day.tempC), fill: Twin.Palette.paper))
        for e in auto {
            out.append(Item(id: e.id.uuidString, emoji: e.kind.emoji, text: e.title, fill: Twin.Palette.paper))
        }
        return out
    }
}

// MARK: - You logged today

/// What the user tagged today (pink "+" sheet). New tags pop in.
struct TodayLoggedCard: View {
    let exposures: [Exposure]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "You logged today")
            if exposures.isEmpty {
                Text("Nothing yet. A new soap, a new food, a sweaty workout? Add it in one tap.")
                    .font(Twin.Typeface.sans(14))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StickerWrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(exposures) { e in
                    TodayEmojiSticker(emoji: e.kind.emoji, text: e.title, fill: Twin.Palette.paper)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Add").font(Twin.Typeface.sans(12, .bold))
                    }
                    .foregroundStyle(Twin.Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, style: StrokeStyle(lineWidth: Twin.Stroke.ink, dash: [3, 2.5])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Add something you ran into today")
            }
        }
        .twinCard()
    }
}

// MARK: - Empty state

struct TodayEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 52, height: 52)
                .sticker(Twin.Palette.yellow)
            Text("No data yet").font(Twin.Typeface.title).foregroundStyle(Twin.Palette.ink)
            Text("Wear your watch tonight. Your first night shows up here in the morning.")
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
    }
}

// MARK: - Small shared pieces (Today + Trends)

/// Sticker with an emoji and a label. (Own view: the shared `Sticker` treats emoji whose first
/// scalar is text-style, like 🌫️ 🌡️ 🏋️, as SF Symbol names.)
struct TodayEmojiSticker: View {
    var emoji: String?
    var text: String
    var fill: Color = Twin.Palette.paper
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 5) {
            if let emoji { Text(emoji).font(.system(size: size - 1)) }
            Text(text).font(Twin.Typeface.sans(size, .bold)).lineLimit(1)
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sticker(fill)
    }
}

/// Pops a sticker in (scale + fade) after `delay`; fade only with Reduce Motion.
struct TodayPopIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : Twin.Motion.bouncy.delay(delay)) { shown = true }
            }
    }
}

/// Left-to-right wrapping layout for stickers and chips.
struct StickerWrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
            if x > 0, x + sz.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + sz.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
