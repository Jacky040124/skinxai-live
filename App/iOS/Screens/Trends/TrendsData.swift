import SwiftUI
import EczemaKit

/// Range of the Trends chart. "All" is the same 14 nights: the story starts 14 nights ago.
enum TrendsRange: String, CaseIterable, Identifiable, Hashable {
    case week, twoWeeks, all
    var id: Self { self }
    var title: String {
        switch self { case .week: "7 nights"; case .twoWeeks: "14 nights"; case .all: "All" }
    }
    /// How many nights the chart shows (the last ones).
    var nights: Int { self == .week ? min(7, StageStory.nightCount) : StageStory.nightCount }
    /// Top bar subtitle: "Last 14 nights".
    var subtitle: String { "Last \(nights) nights" }
    /// Whether night `i` is on the chart.
    func shows(_ night: Int) -> Bool { night >= StageStory.nightCount - nights && night < StageStory.nightCount }
}

/// Something that changed during the 14 nights ("What changed"), with the night it points at.
struct TrendsChange: Identifiable {
    let id: String
    let emoji: String
    let fill: Color
    let title: String
    /// "first used Tue Oct 20"
    let detail: String
    /// The night its marker sits on (tapping the row selects it).
    let night: Int
}

/// The selected night, as the detail strip under the chart says it.
struct TrendsNight: Equatable {
    /// "LAST NIGHT", "NIGHT OF TUE OCT 20"
    let eyebrow: String
    let minutes: Int
    /// "2–4 AM worst", "19 episodes", "calm"
    let note: String
    let hot: Bool
    /// "3.4× usual" (hot nights)
    let ratio: String
}

/// What the Trends tab shows, all from `StageStory`.
enum TrendsStory {
    private static var calendar: Calendar { TodayStory.calendar }

    /// Minutes at the top of the chart: a little above the worst night (41 → 48).
    static var scaleTop: Double { (Double(StageStory.nights.max() ?? 1) * 1.17).rounded(.up) }

    /// Night of the exams marker: the middle of the midterms.
    static var examsMarkerNight: Int {
        let e = StageStory.examNights
        return e.lowerBound + (e.upperBound - e.lowerBound) / 2
    }

    static func bars(_ range: TrendsRange, now: Date = Date()) -> [NightsChart.Bar] {
        let cal = calendar
        let first = StageStory.nightCount - range.nights
        let nights = Array(first..<StageStory.nightCount)
        let dates = nights.map { StageStory.nightDate($0, now: now, calendar: cal) }
        // Month labels where the range starts and where a new month begins; the first one is
        // dropped when a new month begins right after it (they would run into each other).
        var months = Set(nights.indices.filter { cal.component(.day, from: dates[$0]) == 1 })
        if let next = months.min(), next < 3 {} else { months.insert(0) }
        return nights.indices.map { k in
            let i = nights[k]
            let date = dates[k]
            return NightsChart.Bar(
                id: i,
                value: Double(StageStory.nights[i]),
                hot: StageStory.isFlare(i),
                day: "\(cal.component(.day, from: date))",
                month: months.contains(k) ? StageStory.month(date, calendar: cal).uppercased() : nil,
                isLast: i == StageStory.lastNightIndex,
                accessibility: accessibility(i, date: date))
        }
    }

    /// The markers above the chart: exams and the new wash on the top row, dry air on the row under it
    /// (it ends at its stem, so it stays inside the card over the last night).
    static var markers: [NightsChart.Marker] {
        [NightsChart.Marker(id: "exams", bar: examsMarkerNight, emoji: "📚", text: "exams", fill: Twin.Palette.paper, row: 0),
         NightsChart.Marker(id: "wash", bar: StageStory.bodyWashNight, emoji: "🧴", text: "new wash", fill: Twin.Palette.pink, row: 0),
         NightsChart.Marker(id: "dry", bar: StageStory.dryAirNight, emoji: "💧", text: "dry air", fill: Twin.Palette.orange,
                            row: 1, trailing: true)]
    }

    /// "What changed": the body wash, the dry night, the midterms (dates computed from now).
    static func changes(now: Date = Date()) -> [TrendsChange] {
        let cal = calendar
        let wash = StageStory.nightDate(StageStory.bodyWashNight, now: now, calendar: cal)
        let dry = StageStory.nightDate(StageStory.dryAirNight, now: now, calendar: cal)
        let exams = StageStory.examNights
        let examsText = StageStory.monthDayRange(StageStory.nightDate(exams.lowerBound, now: now, calendar: cal),
                                                 StageStory.nightDate(exams.upperBound, now: now, calendar: cal), calendar: cal)
        return [
            TrendsChange(id: "wash", emoji: "🧴", fill: Twin.Palette.pink, title: "New body wash",
                         detail: "first used \(dayText(wash))", night: StageStory.bodyWashNight),
            TrendsChange(id: "dry", emoji: "💧", fill: Twin.Palette.orange, title: "Dry air",
                         detail: "humidity \(StageStory.humidity[StageStory.dryAirNight])% on \(dayText(dry))",
                         night: StageStory.dryAirNight),
            TrendsChange(id: "exams", emoji: "📚", fill: Twin.Palette.paper, title: "Midterm exams",
                         detail: examsText, night: examsMarkerNight),
        ]
    }

    /// The detail strip for night `i`.
    static func night(_ i: Int, now: Date = Date()) -> TrendsNight {
        let i = min(max(i, 0), StageStory.lastNightIndex)
        let last = i == StageStory.lastNightIndex
        let hot = StageStory.isFlare(i)
        let date = StageStory.nightDate(i, now: now, calendar: calendar)
        let note: String
        if last {
            note = "\(StageStory.LastNight.worst) worst"
        } else if hot {
            note = "\(StageStory.episodes[i]) episodes"
        } else {
            note = "calm"
        }
        return TrendsNight(eyebrow: last ? "LAST NIGHT" : "NIGHT OF \(dayText(date))".uppercased(),
                           minutes: StageStory.nights[i], note: note, hot: hot,
                           ratio: String(format: "%.1f× usual", StageStory.ratio(i)))
    }

    /// "Tue Oct 20"
    static func dayText(_ date: Date) -> String {
        "\(StageStory.weekday(date, short: true, calendar: calendar)) \(StageStory.monthDay(date, calendar: calendar))"
    }

    /// "Tuesday, Oct 20: 17 minutes, above your usual. New wash."
    private static func accessibility(_ i: Int, date: Date) -> String {
        var text = "\(StageStory.weekday(date, calendar: calendar)), \(StageStory.monthDay(date, calendar: calendar)): "
            + "\(StageStory.nights[i]) minutes"
        if i == StageStory.lastNightIndex { text = "Last night, " + text }
        text += StageStory.isFlare(i) ? ", above your usual." : "."
        for marker in markers where marker.bar == i { text += " \(marker.text.prefix(1).uppercased() + marker.text.dropFirst())." }
        return text
    }
}
