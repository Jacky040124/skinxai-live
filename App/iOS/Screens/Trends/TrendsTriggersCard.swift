import SwiftUI
import EczemaKit

// MARK: - 4. Trigger impact

/// For each possible trigger: average minutes on nights with it against nights without, as two bars,
/// the difference and a verdict sticker (strong / weak / no link). Every factor but the body wash is
/// compared on the nights without the body wash, so its flare nights don't color the others.
struct TrendsTriggersCard: View {
    let onAsk: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var impacts: [StageHistory.Impact] {
        StageHistory.impacts.sorted { $0.difference > $1.difference }
    }

    private var takeaway: (String, String) {
        let list = StageHistory.impacts
        let strong = list.filter { $0.verdict == .strong }
        guard strong.count == 1, let top = strong.first else {
            return ("No single trigger stands out.", "Keep tracking; patterns take a few weeks.")
        }
        let weak = list.filter { $0.verdict == .weak }.map { Self.short($0.factor) }
        let none = list.filter { $0.verdict == .none }.map { Self.short($0.factor) }
        var parts: [String] = []
        if !weak.isEmpty { parts.append("\(Self.joined(weak)) \(weak.count == 1 ? "adds" : "add") a little") }
        if !none.isEmpty { parts.append("\(Self.joined(none)) don't") }
        var rest = parts.joined(separator: "; ") + "."
        rest = rest.prefix(1).uppercased() + rest.dropFirst()
        return ("Only the \(Self.title(top.factor).lowercased()) stands out: \(signed(top.roundedDifference)) min.", rest)
    }

    /// "a, b and c"
    private static func joined(_ items: [String]) -> String {
        items.count <= 1 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// The factor in a sentence: "late gym", "new clothes (washed first)".
    static func short(_ f: StageHistory.Factor) -> String {
        switch f {
        case .bodyWash: return "the new body wash"
        case .dryAir: return "dry air"
        case .exams: return "exams"
        case .gym: return "late gym"
        case .shortSleep: return "short sleep"
        case .newClothes: return "new clothes (washed first)"
        }
    }

    var body: some View {
        let t = takeaway
        let scale = max(30, (impacts.map { max($0.withMinutes, $0.withoutMinutes) }.max() ?? 30).rounded(.up))
        TrendsTakeawayCard(eyebrow: "Trigger impact", meta: "MIN / NIGHT", lead: t.0, rest: t.1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(impacts.enumerated()), id: \.element.id) { k, impact in
                    if k > 0 { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
                    row(impact, k: k, scale: scale)
                }
                footer
                    .padding(.top, 12)
            }
        }
        .onFirstSight {
            if reduceMotion { withAnimation(.easeOut(duration: 0.35)) { grown = true } } else { grown = true }
        }
    }

    // MARK: Row

    private func row(_ i: StageHistory.Impact, k: Int, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(Self.emoji(i.factor))
                    .font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .sticker(i.verdict == .strong ? Twin.Palette.pink : Twin.Palette.paper)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(i.factor))
                        .font(Twin.Typeface.sans(15, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(Self.detail(i))
                        .font(Twin.Typeface.mono(10))
                        .tracking(0.2)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(signed(i.roundedDifference))
                            .font(Twin.Typeface.sans(20, .bold))
                            .tracking(-0.6)
                            .monospacedDigit()
                        Text("min")
                            .font(Twin.Typeface.sans(12, .medium))
                            .foregroundStyle(Twin.Palette.inkHint)
                    }
                    .foregroundStyle(Twin.Palette.ink)
                    verdict(i.verdict)
                        .modifier(TodayStamp(delay: 0.5 + Double(k) * 0.08))
                }
            }
            VStack(spacing: 4) {
                bar("with", value: i.withMinutes, scale: scale, fill: Self.withFill(i.verdict),
                    edged: i.verdict != .none, delay: 0.15 + Double(k) * 0.08)
                bar("without", value: i.withoutMinutes, scale: scale, fill: Twin.Palette.ink.opacity(0.15),
                    edged: false, delay: 0.2 + Double(k) * 0.08)
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.title(i.factor)): \(Int(i.withMinutes.rounded())) minutes a night with it, "
                            + "\(Int(i.withoutMinutes.rounded())) without, \(signed(i.roundedDifference)) minutes. \(Self.verdictText(i.verdict)).")
    }

    private func bar(_ label: String, value: Double, scale: Double, fill: Color, edged: Bool, delay: Double) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(Twin.Typeface.mono(9, bold: true))
                .tracking(0.3)
                .foregroundStyle(Twin.Palette.inkHint)
                .frame(width: 56, alignment: .leading)
            GeometryReader { g in
                let shape = UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous)
                HStack(spacing: 6) {
                    shape.fill(fill)
                        .overlay { if edged { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
                        .frame(width: max(3, CGFloat(value / scale) * (g.size.width - 30)))
                        .scaleEffect(x: grown || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                        .animation(reduceMotion ? nil : Twin.Motion.spring.delay(delay), value: grown)
                    Text("\(Int(value.rounded()))")
                        .font(Twin.Typeface.mono(10, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize()
                        .opacity(grown ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(delay + 0.3), value: grown)
                }
            }
            .frame(height: 12)
        }
    }

    private func verdict(_ v: StageHistory.Verdict) -> some View {
        Text(Self.verdictText(v))
            .font(Twin.Typeface.sans(11, .bold))
            .foregroundStyle(Twin.Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .fixedSize()
            .sticker(v == .strong ? Twin.Palette.orange : (v == .weak ? Twin.Palette.orangeSoft : Twin.Palette.paper))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other factors are compared on nights without the body wash.")
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
            Text("Association, not proof. Claude can help you test it.")
                .font(Twin.Typeface.sans(14, .medium))
                .foregroundStyle(Twin.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAsk) {
                HStack(spacing: 8) {
                    Text("✶").font(.system(size: 15, weight: .bold))
                    Text("Test it with Claude")
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 46))
            .accessibilityHint("Opens Insight")
        }
    }

    // MARK: Words

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "±0") }

    static func title(_ f: StageHistory.Factor) -> String {
        switch f {
        case .bodyWash: return "New body wash"
        case .dryAir: return "Dry air under \(StageStory.dryBelowPercent)%"
        case .exams: return "Exam week"
        case .gym: return "Late gym / sweat"
        case .shortSleep: return "Short sleep the night before"
        case .newClothes: return "New clothes"
        }
    }

    static func emoji(_ f: StageHistory.Factor) -> String {
        switch f {
        case .bodyWash: return "🧴"
        case .dryAir: return "💧"
        case .exams: return "📚"
        case .gym: return "🏋️"
        case .shortSleep: return "😴"
        case .newClothes: return "👕"
        }
    }

    /// "4 NIGHTS WITH · 70 WITHOUT"
    static func detail(_ i: StageHistory.Impact) -> String {
        let extra = i.factor == .newClothes ? " · WASHED FIRST" : ""
        return "\(i.withNights) NIGHTS WITH · \(i.withoutNights) WITHOUT\(extra)"
    }

    static func verdictText(_ v: StageHistory.Verdict) -> String {
        switch v {
        case .strong: return "Strong link"
        case .weak: return "Weak link"
        case .none: return "No link"
        }
    }

    static func withFill(_ v: StageHistory.Verdict) -> Color {
        switch v {
        case .strong: return Twin.Palette.orange
        case .weak: return Twin.Palette.orangeSoft
        case .none: return Twin.Palette.ink.opacity(0.32)
        }
    }
}
