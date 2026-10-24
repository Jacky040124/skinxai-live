import SwiftUI
import EczemaKit

// MARK: - Call to action (Claude)

/// Pink-soft card with an ink edge and a shimmer sweep (the Claude call-to-action).
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
            HStack(alignment: .center, spacing: 12) {
                iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Twin.Typeface.headline)
                        .foregroundStyle(Twin.Palette.ink)
                    Text(subtitle)
                        .font(Twin.Typeface.subhead)
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    accessory()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .offset(x: sweeps % 2 == 1 ? 3 : 0)
            }
            .padding(14)
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

// MARK: - Sleep / Stress mini cards

/// "SLEEP 5.1 h · ■ woke up 4×": the value counts up, spark bars show the last nights (last night
/// highlighted, your usual dashed), and a square says worse (orange) or fine (lime).
struct TodayMiniCard: View {
    let title: String
    let value: Double
    let decimals: Int
    let unit: String
    let note: String
    /// Worse than usual: orange square and last bar; otherwise lime square and an ink bar.
    let worse: Bool
    /// The last nights, last night last.
    let history: [Double]
    var usual: Double? = nil
    var delay: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                CountUp(value: value, decimals: decimals, font: Twin.Typeface.sans(34, .bold), delay: delay)
                    .tracking(-1)
                Text(unit).font(Twin.Typeface.sans(15)).foregroundStyle(Twin.Palette.inkHint)
                Spacer(minLength: 6)
                SparkBars(values: history, highlight: worse ? Twin.Palette.orange : Twin.Palette.ink,
                          usual: usual, delay: delay + 0.25)
                    .frame(width: 44, height: 22)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(worse ? Twin.Palette.orange : Twin.Palette.lime)
                    .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                Text(note)
                    .font(Twin.Typeface.footnote)
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .twinCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(String(format: "%.\(decimals)f", value)) \(unit == "h" ? "hours" : unit), \(note)")
    }
}

// MARK: - Around you · auto

/// Humidity, air quality, pollen and temperature where he is, read automatically. Dry air is orange.
struct TodayAroundYouCard: View {
    private struct Item: Identifiable { let id: String; let emoji: String; let text: String; let fill: Color }

    private var items: [Item] {
        let humidity = StageStory.LastNight.humidity
        let dry = humidity < StageStory.dryBelowPercent
        return [
            Item(id: "humidity", emoji: "💧", text: dry ? "Humidity \(humidity)% · dry" : "Humidity \(humidity)%",
                 fill: dry ? Twin.Palette.orange : Twin.Palette.paper),
            Item(id: "aqi", emoji: "🍃", text: "Air quality \(StageStory.airQuality) · \(StageStory.airQualityLabel)",
                 fill: Twin.Palette.paper),
            Item(id: "pollen", emoji: "🌼", text: "Pollen · \(StageStory.pollen)", fill: Twin.Palette.paper),
            Item(id: "temperature", emoji: "🌡️", text: "\(StageStory.LastNight.highF)°F", fill: Twin.Palette.paper),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Around you · auto")
            StickerWrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    TodayEmojiSticker(emoji: item.emoji, text: item.text, fill: item.fill)
                        .modifier(TodayPopIn(delay: 0.55 + Double(i) * 0.07))
                }
            }
        }
        .twinCard(fill: Twin.Palette.cream)
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
