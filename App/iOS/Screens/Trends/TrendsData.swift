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

/// What the Trends tab shows, all from `StageStory` and its longer history `StageHistory`.
///
/// Nights are numbered like `StageStory`'s (0 = oldest of the 14 … 13 = last night). The 60 calm nights
/// of `StageHistory` before them have negative numbers (−60 … −1); "All time" shows all 74. Claude's
/// tools still read only `StageStory`'s 14.
enum TrendsStory {
    private static var calendar: Calendar { TodayStory.calendar }

    // MARK: Nights

    /// Nights before the story's 14: `StageHistory`'s 60.
    static let earlierNights: Int = StageHistory.earlierCount
    /// Every night on the chart, oldest first.
    static var nightIDs: ClosedRange<Int> { StageHistory.nightIDs }
    static var nightCount: Int { nightIDs.count }

    /// Minutes of scratching on night `i`.
    static func minutes(_ i: Int) -> Int { StageHistory.night(i).minutes }
    /// Scratching episodes on night `i`.
    static func episodes(_ i: Int) -> Int { StageHistory.night(i).episodes }
    /// Humidity on the day night `i` started, percent.
    static func humidity(_ i: Int) -> Int { StageHistory.night(i).humidity }
    /// Above 1.5 × your usual (the orange bars).
    static func isFlare(_ i: Int) -> Bool { StageHistory.night(i).flare }
    /// Humidity under 35%.
    static func isDry(_ i: Int) -> Bool { StageHistory.night(i).dry }
    /// The day's high, °F.
    static func highF(_ i: Int) -> Int { StageHistory.night(i).highF }
    /// A high of 85 °F or more.
    static func isHot(_ i: Int) -> Bool { highF(i) >= hotFromF }
    static let hotFromF = 85

    /// The middle night of each exam week, oldest first (the midterms' is `examsMarkerNight`).
    static var examMarkerNights: [Int] {
        var runs: [[Int]] = []
        for n in StageHistory.nights where n.exams {
            if let last = runs.last?.last, last == n.id - 1 { runs[runs.count - 1].append(n.id) } else { runs.append([n.id]) }
        }
        return runs.map { $0[($0.count - 1) / 2] }
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
                highF: highF(i),
                hotDay: isHot(i),
                accessibility: accessibility(i, date: date))
        }
    }

    /// The markers above the chart: exams and the new wash on the top row, dry air on the row under it
    /// (over last night it ends at its stem, so it stays inside the card). Every run of dry days gets
    /// one, on its first day; earlier exam weeks get their own "exams" flag. The earlier flare's two new
    /// things (the wool sweater and the detergent sample, bought the same day) get one flag each on
    /// that day, one above the other, both pink: the data can't tell them apart.
    static var markers: [NightsChart.Marker] {
        var list = examMarkerNights.filter { $0 != examsMarkerNight }.map {
            NightsChart.Marker(id: "exams\($0)", bar: $0, emoji: "📚", text: "exams", fill: Twin.Palette.paper, row: 0)
        }
        list += [NightsChart.Marker(id: "exams", bar: examsMarkerNight, emoji: "📚", text: "exams", fill: Twin.Palette.paper, row: 0),
                 NightsChart.Marker(id: "wash", bar: StageStory.bodyWashNight, emoji: "🧴", text: "new wash", fill: Twin.Palette.pink, row: 0),
                 NightsChart.Marker(id: "sweater", bar: StageHistory.earlierSuspectsBoughtNight, emoji: "👕", text: "new sweater",
                                    fill: Twin.Palette.pink, row: 0, leading: true),
                 NightsChart.Marker(id: "detergent", bar: StageHistory.earlierSuspectsBoughtNight, emoji: "🧺", text: "new detergent",
                                    fill: Twin.Palette.pink, row: 1, leading: true)]
        // One flag per run of dry days (on its first day): flags on neighboring nights would overlap;
        // the humidity row still marks each dry day.
        for i in nightIDs where isDry(i) && !(nightIDs.contains(i - 1) && isDry(i - 1)) {
            var run = 1
            while nightIDs.contains(i + run) && isDry(i + run) { run += 1 }
            list.append(NightsChart.Marker(id: i == StageStory.dryAirNight ? "dry" : "dry\(i)", bar: i, emoji: "💧",
                                           text: run > 1 ? "\(run) dry days" : "dry air",
                                           fill: Twin.Palette.orange, row: 1, trailing: i == StageStory.lastNightIndex))
        }
        return list
    }

    /// The sentence above the chart about the weather on the nights shown: "Weather stayed normal while
    /// scratching rose; the dry day came after." It checks the day each rise began (the first night of
    /// every run of orange bars), then whether any later flare night had odd weather.
    static func weatherTakeaway(shown: Int) -> (lead: String, rest: String) {
        let ids = Array(nightIDs.suffix(max(shown, 1)))
        let normal = { (i: Int) in !isDry(i) && !isHot(i) }
        let flares = ids.filter(isFlare)
        guard !flares.isEmpty else { return ("Weather and scratching", "both stayed normal.") }
        let starts = flares.filter { !flares.contains($0 - 1) }
        guard starts.allSatisfy(normal) else { return ("Scratching rose", "on days with unusual weather.") }
        let odd = flares.filter { !normal($0) }
        guard !odd.isEmpty else { return ("Weather stayed normal", "while scratching rose.") }
        let what = odd.allSatisfy(isDry) ? "dry day" : "unusual day"
        return ("Weather stayed normal", "while scratching rose; the \(what)\(odd.count == 1 ? "" : "s") came after.")
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
        text += " Humidity \(humidity(i))%\(isDry(i) ? ", dry" : ""), high \(highF(i))°F."
        for marker in markers where marker.bar == i && !marker.id.hasPrefix("dry") {
            text += " \(marker.text.prefix(1).uppercased() + marker.text.dropFirst())."
        }
        return text
    }
}

// MARK: - Launch arguments (debug builds: screenshots)

enum TrendsLaunch {
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
