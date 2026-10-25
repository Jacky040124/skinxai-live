import SwiftUI
import EczemaKit

// MARK: - 4. Trigger impact

/// For each possible trigger: average minutes on nights with it against nights without, as two bars,
/// the difference and a verdict sticker (strong / possible / weak / no link). Each factor is compared on
/// the nights outside the flares it can't explain, so one flare's nights don't color the others. The
/// wool sweater and the detergent sample were used on exactly the same nights: same numbers, "Possible
/// link", and a note between their rows that the data can't separate them (Claude can, by asking).
struct TrendsTriggersCard: View {
    let onAsk: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var now = Date()

    private var impacts: [StageHistory.Impact] {
        let order = StageHistory.Factor.allCases
        return StageHistory.impacts.sorted {
            $0.roundedDifference != $1.roundedDifference ? $0.difference > $1.difference
                : order.firstIndex(of: $0.factor)! < order.firstIndex(of: $1.factor)!
        }
    }

    /// "Oct 6–9": the nights the sweater and the sample were used.
    private var earlierFlareText: String {
        let cal = TodayStory.calendar
        let f = StageHistory.earlierFlareNights
        return StageStory.monthDayRange(StageStory.nightDate(f.lowerBound, now: now, calendar: cal),
                                        StageStory.nightDate(f.upperBound, now: now, calendar: cal), calendar: cal)
    }

    private var takeaway: (String, String) {
        let list = StageHistory.impacts
        let strong = list.filter { $0.verdict == .strong }
        let possible = list.filter { $0.verdict == .possible }
        guard let top = strong.max(by: { $0.difference < $1.difference }) ?? possible.first else {
            return ("No single trigger stands out.", "Keep tracking; patterns take a few weeks.")
        }
        var sentences: [String] = []
        if possible.count >= 2 {
            let names = Self.joined(possible.map { Self.short($0.factor) })
            sentences.append("The \(earlierFlareText) flare fits \(names) equally (\(signed(possible[0].roundedDifference)) min each), "
                             + "so the data alone can't tell them apart. Ask Claude to narrow it down.")
        }
        let weak = list.filter { $0.verdict == .weak }.map { Self.short($0.factor) }
        let none = list.filter { $0.verdict == .none }
        var parts: [String] = []
        if !weak.isEmpty { parts.append("\(Self.joined(weak)) \(weak.count == 1 ? "adds" : "add") a little") }
        if !none.isEmpty { parts.append(parts.isEmpty ? "\(Self.joined(none.map { Self.short($0.factor) })) don't" : "the rest don't") }
        if !parts.isEmpty {
            let line = parts.joined(separator: "; ") + "."
            sentences.append(line.prefix(1).uppercased() + line.dropFirst())
        }
        let lead = strong.count == 1 ? "The \(Self.title(top.factor).lowercased()) stands out: \(signed(top.roundedDifference)) min."
            : "\(strong.count + possible.count) factors stand out."
        return (lead, sentences.joined(separator: " "))
    }

    /// "a, b and c"
    private static func joined(_ items: [String]) -> String {
        items.count <= 1 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// The factor in a sentence: "late gym", "washed new clothes".
    static func short(_ f: StageHistory.Factor) -> String {
        switch f {
        case .bodyWash: return "the new body wash"
        case .woolSweater: return "the wool sweater"
        case .sampleDetergent: return "the detergent sample"
        case .dryAir: return "dry air"
        case .exams: return "exams"
        case .gym: return "late gym"
        case .shortSleep: return "short sleep"
        case .newClothes: return "washed new clothes"
        }
    }

    var body: some View {
        let t = takeaway
        let scale = max(30, (impacts.map { max($0.withMinutes, $0.withoutMinutes) }.max() ?? 30).rounded(.up))
        TrendsTakeawayCard(eyebrow: "Trigger impact", meta: "MIN / NIGHT", lead: t.0, rest: t.1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(impacts.enumerated()), id: \.element.id) { k, impact in
                    if k > 0, let twin = impact.sameNightsAs, impacts[k - 1].factor == twin {
                        cantSeparate(impact)
                    } else if k > 0 {
                        Rectangle().fill(Twin.Palette.hairline).frame(height: 1)
                    }
                    row(impact, k: k, scale: scale)
                }
                footer
                    .padding(.top, 12)
            }
        }
        .onFirstSight {
            if reduceMotion { withAnimation(.easeOut(duration: 0.35)) { grown = true } } else { grown = true }
        }
        .onNewDay { now = Date() }
    }

    // MARK: Row

    /// Between the two factors that share their nights: "↕ Same 4 nights, Oct 6–9 · can't separate".
    private func cantSeparate(_ i: StageHistory.Impact) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .bold))
            Text("SAME \(i.withNights) NIGHTS, \(earlierFlareText.uppercased()) · CAN'T SEPARATE")
                .font(Twin.Typeface.mono(10, bold: true))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Twin.Palette.orangeSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
            .strokeBorder(Twin.Palette.ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .padding(.leading, 44)
        .padding(.vertical, 2)
        .opacity(grown ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.6), value: grown)
        .accessibilityLabel("The same \(i.withNights) nights, \(earlierFlareText): the data can't separate these two.")
    }

    private func row(_ i: StageHistory.Impact, k: Int, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TwinIconView(emoji: Self.emoji(i.factor), size: 20)
                    .frame(width: 34, height: 34)
                    .sticker(i.verdict == .strong || i.verdict == .possible ? Twin.Palette.pink : Twin.Palette.paper)
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
            .sticker(v == .strong ? Twin.Palette.orange : (v == .weak || v == .possible ? Twin.Palette.orangeSoft : Twin.Palette.paper))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each factor is compared on the nights outside the other flares.")
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
                    Text("Ask Claude to narrow it down")
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
        case .woolSweater: return "New wool sweater"
        case .sampleDetergent: return "New detergent (sample)"
        case .dryAir: return "Dry air under \(StageStory.dryBelowPercent)%"
        case .exams: return "Exam week"
        case .gym: return "Late gym / sweat"
        case .shortSleep: return "Short sleep the night before"
        case .newClothes: return "Other new clothes, washed"
        }
    }

    static func emoji(_ f: StageHistory.Factor) -> String {
        switch f {
        case .bodyWash: return "🧴"
        case .woolSweater: return "👕"
        case .sampleDetergent: return "🧺"
        case .dryAir: return "💧"
        case .exams: return "📚"
        case .gym: return "🏋️"
        case .shortSleep: return "😴"
        case .newClothes: return "🛍️"
        }
    }

    /// "4 NIGHTS WITH · 70 WITHOUT"
    static func detail(_ i: StageHistory.Impact) -> String {
        "\(i.withNights) NIGHTS WITH · \(i.withoutNights) WITHOUT"
    }

    static func verdictText(_ v: StageHistory.Verdict) -> String {
        switch v {
        case .strong: return "Strong link"
        case .possible: return "Possible link"
        case .weak: return "Weak link"
        case .none: return "No link"
        }
    }

    static func withFill(_ v: StageHistory.Verdict) -> Color {
        switch v {
        case .strong, .possible: return Twin.Palette.orange
        case .weak: return Twin.Palette.orangeSoft
        case .none: return Twin.Palette.ink.opacity(0.32)
        }
    }
}
