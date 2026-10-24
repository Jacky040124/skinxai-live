import SwiftUI
import EczemaKit

/// Range of the Trends chart: the last 7 nights, or every night there is ("All time"; more than 14
/// nights scroll sideways).
enum TrendsRange: String, CaseIterable, Identifiable, Hashable {
    case week, all
    var id: Self { self }
    var title: String { self == .week ? "7 nights" : "All time" }
    /// How many nights the chart shows (the last ones).
    var nights: Int { self == .week ? min(7, TrendsStory.nightCount) : TrendsStory.nightCount }
    /// Top bar subtitle: "Last 7 nights", "All time · 14 nights".
    var subtitle: String { self == .week ? "Last \(nights) nights" : "All time · \(nights) nights" }
    /// Whether night `night` is on the chart.
    func shows(_ night: Int) -> Bool {
        TrendsStory.nightIDs.contains(night) && night > StageStory.lastNightIndex - nights
    }
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
    /// "LAST NIGHT · DRY AIR 29%", "TUE OCT 20 · HUMIDITY 49%"
    let eyebrow: String
    let minutes: Int
    /// "2–4 AM worst", "19 episodes", "calm"
    let note: String
    let hot: Bool
    /// "3.4× usual" (hot nights)
    let ratio: String
}

/// What the Trends tab shows, all from `StageStory`.
///
/// Nights are numbered like `StageStory`'s (0 = oldest of the 14 … 13 = last night). Debug builds can
/// put calm nights before them for screenshots of a longer history (`-trendsNights 30`): those have
/// negative numbers and never reach `StageStory` or Claude's tools.
enum TrendsStory {
    private static var calendar: Calendar { TodayStory.calendar }

    // MARK: Nights

    /// Nights before the story's 14 (debug screenshots only; 0 in normal use).
    static let earlierNights: Int = max(0, (TrendsLaunch.nights ?? 0) - StageStory.nightCount)
    /// Every night on the chart, oldest first.
    static var nightIDs: ClosedRange<Int> { -earlierNights...StageStory.lastNightIndex }
    static var nightCount: Int { nightIDs.count }

    /// Minutes of scratching on night `i`.
    static func minutes(_ i: Int) -> Int { i >= 0 ? StageStory.nights[i] : Earlier.minutes(i) }
    /// Scratching episodes on night `i`.
    static func episodes(_ i: Int) -> Int { i >= 0 ? StageStory.episodes[i] : Earlier.episodes(i) }
    /// Humidity on the day night `i` started, percent.
    static func humidity(_ i: Int) -> Int { i >= 0 ? StageStory.humidity[i] : Earlier.humidity(i) }
    /// Above 1.5 × your usual (the orange bars).
    static func isFlare(_ i: Int) -> Bool { i >= 0 ? StageStory.isFlare(i) : Double(minutes(i)) > StageStory.flareFactor * Double(StageStory.usual) }
    /// Humidity under 35%.
    static func isDry(_ i: Int) -> Bool { humidity(i) < StageStory.dryBelowPercent }

    /// Calm nights before the story (debug screenshots): around the usual, one dry day among them.
    private enum Earlier {
        static let minutesCycle = [11, 9, 13, 10, 12, 8, 14, 11, 10, 13, 9, 12, 15, 10, 11, 9, 12, 13, 10, 14]
        static let humidityCycle = [51, 54, 48, 50, 56, 53, 49, 47, 33, 52, 55, 50, 48, 53, 57, 51, 49, 54, 52, 50]
        private static func k(_ i: Int) -> Int { (-i - 1) % minutesCycle.count }
        static func minutes(_ i: Int) -> Int { minutesCycle[k(i)] }
        static func humidity(_ i: Int) -> Int { humidityCycle[k(i)] }
        static func episodes(_ i: Int) -> Int { max(4, Int((Double(minutes(i)) * 0.8).rounded())) }
    }

    // MARK: Chart

    /// Minutes at the top of the chart: a little above the worst night (41 → 48).
    static var scaleTop: Double { (Double(nightIDs.map(minutes).max() ?? 1) * 1.17).rounded(.up) }

    /// Night of the exams marker: the middle of the midterms.
    static var examsMarkerNight: Int {
        let e = StageStory.examNights
        return e.lowerBound + (e.upperBound - e.lowerBound) / 2
    }

    /// Every night (the chart slides the ones before the range out of view).
    static func bars(now: Date = Date()) -> [NightsChart.Bar] {
        let cal = calendar
        return nightIDs.map { i in
            let date = StageStory.nightDate(i, now: now, calendar: cal)
            return NightsChart.Bar(
                id: i,
                value: Double(minutes(i)),
                hot: isFlare(i),
                day: "\(cal.component(.day, from: date))",
                month: StageStory.month(date, calendar: cal).uppercased(),
                startsMonth: cal.component(.day, from: date) == 1,
                isLast: i == StageStory.lastNightIndex,
                humidity: humidity(i),
                dry: isDry(i),
                accessibility: accessibility(i, date: date))
        }
    }

    /// The markers above the chart: exams and the new wash on the top row, dry air on the row under it
    /// (over last night it ends at its stem, so it stays inside the card). Every dry night gets one,
    /// like its orange humidity cell.
    static var markers: [NightsChart.Marker] {
        var list = [NightsChart.Marker(id: "exams", bar: examsMarkerNight, emoji: "📚", text: "exams", fill: Twin.Palette.paper, row: 0),
                    NightsChart.Marker(id: "wash", bar: StageStory.bodyWashNight, emoji: "🧴", text: "new wash", fill: Twin.Palette.pink, row: 0)]
        for i in nightIDs where isDry(i) {
            list.append(NightsChart.Marker(id: i == StageStory.dryAirNight ? "dry" : "dry\(i)", bar: i, emoji: "💧", text: "dry air",
                                           fill: Twin.Palette.orange, row: 1, trailing: i == StageStory.lastNightIndex))
        }
        return list
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
        let i = min(max(i, nightIDs.lowerBound), nightIDs.upperBound)
        let last = i == StageStory.lastNightIndex
        let hot = isFlare(i)
        let date = StageStory.nightDate(i, now: now, calendar: calendar)
        let note: String
        if last {
            note = "\(StageStory.LastNight.worst) worst"
        } else if hot {
            note = "\(episodes(i)) episodes"
        } else {
            note = "calm"
        }
        let air = isDry(i) ? "dry air \(humidity(i))%" : "humidity \(humidity(i))%"
        return TrendsNight(eyebrow: "\(last ? "Last night" : dayText(date)) · \(air)".uppercased(),
                           minutes: minutes(i), note: note, hot: hot,
                           ratio: String(format: "%.1f× usual", Double(minutes(i)) / Double(StageStory.usual)))
    }

    /// "Tue Oct 20"
    static func dayText(_ date: Date) -> String {
        "\(StageStory.weekday(date, short: true, calendar: calendar)) \(StageStory.monthDay(date, calendar: calendar))"
    }

    /// "Tuesday, Oct 20: 17 minutes, above your usual. Humidity 49%. New wash."
    private static func accessibility(_ i: Int, date: Date) -> String {
        var text = "\(StageStory.weekday(date, calendar: calendar)), \(StageStory.monthDay(date, calendar: calendar)): "
            + "\(minutes(i)) minutes"
        if i == StageStory.lastNightIndex { text = "Last night, " + text }
        text += isFlare(i) ? ", above your usual." : "."
        text += " Humidity \(humidity(i))%\(isDry(i) ? ", dry" : "")."
        for marker in markers where marker.bar == i && !marker.id.hasPrefix("dry") {
            text += " \(marker.text.prefix(1).uppercased() + marker.text.dropFirst())."
        }
        return text
    }
}

// MARK: - Launch arguments (debug builds: screenshots)

enum TrendsLaunch {
    /// `-trendsNights 30`: Trends shows 30 nights (calm made-up nights before the 14 real ones), to
    /// see the scrolling "All time" chart. Nothing else in the app changes.
    static var nights: Int? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsNights").flatMap(Int.init)
        #else
        return nil
        #endif
    }

    /// `-trendsScrollBack 9`: after the entrance, the scrolling chart moves back so the night 9 nights
    /// before last night sits at its right edge.
    static var scrollBack: Int? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsScrollBack").flatMap(Int.init)
        #else
        return nil
        #endif
    }
}
