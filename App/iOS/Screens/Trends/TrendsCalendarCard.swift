import SwiftUI
import EczemaKit

// MARK: - 2. Monthly calendar heatmap

/// The last two months as calendars (Mon–Sun), each day shaded by its minutes of scratching: white
/// (calm) → light orange → orange (flare) → red (2.5× usual and up). Today has an ink outline. Small
/// icons mark exams 📚, the new body wash 🧴, the day he got the wool sweater 👕 and the detergent
/// sample 🧺 (both Oct 5, the day before the earlier flare), and dry days 💧.
struct TrendsCalendarCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var now = Date()

    private var calendar: Calendar { TodayStory.calendar }
    private let gap: CGFloat = 4
    private let cellHeight: CGFloat = 40

    /// Minutes → shade: 0 calm (≤ 14), 1 a bit above (15–18), 2 flare (19–29), 3 severe (30+).
    static func level(_ minutes: Int) -> Int {
        switch minutes {
        case ...14: return 0
        case 15...18: return 1
        case 19...29: return 2
        default: return 3
        }
    }

    private static let fills: [Color] = [Twin.Palette.paper, Twin.Palette.orangeSoft, Twin.Palette.orange, Twin.Palette.red]

    /// The first day of the month of last night, and of the month before it.
    private var months: [Date] {
        let last = StageStory.nightDate(StageStory.lastNightIndex, now: now, calendar: calendar)
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: last)) ?? last
        let before = calendar.date(byAdding: .month, value: -1, to: first) ?? first
        return [before, first]
    }

    /// The night that started on `date`'s day, if it is in the history.
    private func night(on date: Date) -> StageHistory.Night? {
        let zero = calendar.startOfDay(for: StageStory.nightDate(0, now: now, calendar: calendar))
        guard let d = calendar.dateComponents([.day], from: zero, to: calendar.startOfDay(for: date)).day,
              StageHistory.nightIDs.contains(d) else { return nil }
        return StageHistory.night(d)
    }

    private var takeaway: (String, String) {
        let date = { (i: Int) in StageStory.nightDate(i, now: now, calendar: calendar) }
        let flare = StageHistory.earlierFlareNights
        let earlier = StageStory.monthDayRange(date(flare.lowerBound), date(flare.upperBound), calendar: calendar)
        let bought = StageStory.monthDay(date(StageHistory.earlierSuspectsBoughtNight), calendar: calendar)
        let wash = StageStory.monthDay(date(StageStory.bodyWashNight), calendar: calendar)
        let calmElse = StageHistory.typicalNights.allSatisfy { Self.level($0.minutes) <= 1 }
        return (calmElse ? "Two flares, calm in between." : "Ups and downs.",
                "\(earlier) came right after the new sweater and detergent (\(bought)). This one began \(wash), with the new body wash.")
    }

    var body: some View {
        let t = takeaway
        TrendsTakeawayCard(eyebrow: "Calendar", meta: "MIN SCRATCHING / NIGHT", lead: t.0, rest: t.1) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(months.enumerated()), id: \.offset) { m, first in
                    month(first, order: m)
                }
                legend
            }
        }
        .onFirstSight {
            withAnimation(reduceMotion ? .easeOut(duration: 0.35) : .linear(duration: 0.01)) { shown = true }
        }
        .onNewDay { now = Date() }
    }

    private func month(_ first: Date, order: Int) -> some View {
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) + 5) % 7   // Monday = 0
        let cells: [Date?] = Array(repeating: nil, count: lead)
            + (0..<days).map { calendar.date(byAdding: .day, value: $0, to: first)
                .flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) } }
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: 7)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(StageStory.month(first, short: false, calendar: calendar)) \(String(calendar.component(.year, from: first)))")
                .font(Twin.Typeface.sans(15, .bold))
                .foregroundStyle(Twin.Palette.ink)
            LazyVGrid(columns: columns, spacing: gap) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(Twin.Typeface.mono(9, bold: true))
                        .foregroundStyle(Twin.Palette.inkHint)
                }
                ForEach(cells.indices, id: \.self) { k in
                    if let date = cells[k] {
                        cell(date, beat: Double(order * 31 + k - lead))
                    } else {
                        Color.clear.frame(height: cellHeight)
                    }
                }
            }
        }
    }

    private func cell(_ date: Date, beat: Double) -> some View {
        let n = night(on: date)
        let today = calendar.isDate(date, inSameDayAs: now)
        let future = !today && date > now
        let level = n.map { Self.level($0.minutes) } ?? 0
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        let icons = n.map(icons) ?? []
        return ZStack(alignment: .topLeading) {
            shape.fill(n == nil ? Color.clear : Self.fills[level])
            if today {
                shape.strokeBorder(Twin.Palette.ink, lineWidth: 2)
            } else if n != nil && level >= 2 {
                shape.strokeBorder(Twin.Palette.ink, lineWidth: 1)
            } else if n != nil {
                shape.strokeBorder(Twin.Palette.hairline, lineWidth: 1)
            }
            Text("\(calendar.component(.day, from: date))")
                .font(Twin.Typeface.mono(9, bold: today || level >= 2))
                .foregroundStyle(future ? Twin.Palette.inkFaint : (level >= 1 || today ? Twin.Palette.ink : Twin.Palette.inkHint))
                .padding(.leading, 4)
                .padding(.top, 3)
            if !icons.isEmpty {
                HStack(spacing: 0) {
                    ForEach(icons, id: \.self) { TwinIconView(emoji: $0, size: 13) }
                }
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 2)
                    .padding(.bottom, 1)
            }
        }
        .frame(height: cellHeight)
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(0.05 + beat * 0.012), value: shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(date, n, today: today))
    }

    /// The day's icons (at most two): exams, the first night of the body wash, the day of the sweater
    /// and the detergent sample, dry air.
    private func icons(_ n: StageHistory.Night) -> [String] {
        var list: [String] = []
        if n.id == StageHistory.earlierSuspectsBoughtNight { list += ["👕", "🧺"] }
        if n.exams { list.append("📚") }
        if n.id == StageStory.bodyWashNight { list.append("🧴") }
        if n.dry { list.append("💧") }
        return Array(list.prefix(2))
    }

    private func accessibility(_ date: Date, _ n: StageHistory.Night?, today: Bool) -> String {
        var text = "\(StageStory.weekday(date, calendar: calendar)), \(StageStory.monthDay(date, calendar: calendar))"
        if today { return text + ", today." }
        guard let n else { return text + ", no data." }
        text += ": \(n.minutes) minutes."
        if n.exams { text += " Exams." }
        if n.id == StageStory.bodyWashNight { text += " First night with the new body wash." }
        if n.id == StageHistory.earlierSuspectsBoughtNight { text += " New wool sweater and a new detergent sample." }
        if n.dry { text += " Dry air, \(n.humidity)%." }
        return text
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { l in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Self.fills[l])
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(l >= 2 ? Twin.Palette.ink : Twin.Palette.hairline, lineWidth: 1))
                            .frame(width: 11, height: 11)
                        Text(["≤14", "15–18", "19–29", "30+"][l])
                    }
                }
                Text("MIN")
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                legendItem("👕", "new sweater")
                legendItem("🧺", "new detergent")
                legendItem("🧴", "new wash")
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                legendItem("📚", "exams")
                legendItem("💧", "dry")
                Spacer(minLength: 0)
            }
        }
        .font(Twin.Typeface.mono(10))
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    private func legendItem(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            TwinIconView(emoji: emoji, size: 12)
            Text(text)
        }
    }
}
