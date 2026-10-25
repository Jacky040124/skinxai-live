import SwiftUI
import EczemaKit

/// Range of the Trends timeline: the last 7 nights, or every night there is ("All time"; more than 21
/// nights scroll sideways).
enum TrendsRange: String, CaseIterable, Identifiable, Hashable {
    case week, all
    var id: Self { self }
    var title: String { self == .week ? "7 nights" : "All time" }
    /// How many nights the chart shows (the last ones).
    var nights: Int { self == .week ? min(7, TrendsStory.nightCount) : TrendsStory.nightCount }
    /// Top bar subtitle: "Last 7 nights", "All time · 74 nights".
    var subtitle: String { self == .week ? "Last \(nights) nights" : "All time · \(nights) nights" }
    /// Whether night `night` is on the chart.
    func shows(_ night: Int) -> Bool {
        TrendsStory.nightIDs.contains(night) && night > StageStory.lastNightIndex - nights
    }
    /// The nights on the chart, oldest first.
    var ids: [Int] { Array(TrendsStory.nightIDs.suffix(nights)) }
}

/// Something on the timeline's event lanes: a new item he bought (on its order date: all the app can
/// read is the order, not when he used it), an exam week, a late workout.
struct TrendsEvent: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case bodywash, sweater, detergent, exams, gym
    }

    let kind: Kind
    /// First and last night (a bought item: the night of its order date, both).
    let start: Int
    let end: Int

    /// "bodywash", "exams:1", "gym:7".
    var id: String {
        switch kind {
        case .bodywash, .sweater, .detergent: return kind.rawValue
        case .exams, .gym: return "\(kind.rawValue):\(start)"
        }
    }

    var emoji: String {
        switch kind {
        case .bodywash: return "🧴"
        case .sweater: return "👕"
        case .detergent: return "🧺"
        case .exams: return "📚"
        case .gym: return "🏋️"
        }
    }

    /// The factor `StageHistory` compares for it.
    var factor: StageHistory.Factor {
        switch kind {
        case .bodywash: return .bodyWash
        case .sweater: return .woolSweater
        case .detergent: return .sampleDetergent
        case .exams: return .exams
        case .gym: return .gym
        }
    }

    /// A new thing he bought (pink on the timeline).
    var isProduct: Bool { [.bodywash, .sweater, .detergent].contains(kind) }

    /// "New body wash", "Wool sweater", "Exams", "Late gym".
    var shortName: String {
        switch kind {
        case .bodywash: return "New body wash"
        case .sweater: return "Wool sweater"
        case .detergent: return "Detergent sample"
        case .exams: return "Exams"
        case .gym: return "Late gym"
        }
    }

    /// The night of the day he ordered it (a bought item): the body wash the day before night 10
    /// (Oct 19), the sweater and the detergent sample on the day of night −5 (Oct 5).
    static func purchaseNight(_ kind: Kind) -> Int? {
        switch kind {
        case .bodywash: return StageStory.bodyWashNight - 1
        case .sweater, .detergent: return StageHistory.earlierSuspectsBoughtNight
        case .exams, .gym: return nil
        }
    }

    /// Every event, oldest first. Bought items sit on their order date only.
    static var all: [TrendsEvent] {
        var list = [TrendsEvent.Kind.sweater, .detergent, .bodywash].compactMap { k in
            purchaseNight(k).map { TrendsEvent(kind: k, start: $0, end: $0) }
        }
        list += TrendsStory.examRuns.map { TrendsEvent(kind: .exams, start: $0.lowerBound, end: $0.upperBound) }
        list += StageHistory.nights.filter(\.gym).map { TrendsEvent(kind: .gym, start: $0.id, end: $0.id) }
        return list.sorted { $0.start < $1.start }
    }

    /// The event with id `id` ("bodywash", "sweater", "detergent", "exams:1", "gym:7"; also plain
    /// "exams" = the midterms and "gym" = the last workout, for launch arguments).
    static func find(_ id: String) -> TrendsEvent? {
        let list = all
        if let e = list.first(where: { $0.id == id }) { return e }
        switch id {
        case "exams": return list.last { $0.kind == .exams }
        case "gym": return list.last { $0.kind == .gym }
        case "wash", "bodyWash": return list.first { $0.kind == .bodywash }
        default: return nil
        }
    }

    /// The events on night `i`.
    static func on(_ i: Int) -> [TrendsEvent] { all.filter { ($0.start...$0.end).contains(i) } }
}

/// The selected night, as the detail strip under the chart says it.
struct TrendsNight: Equatable {
    struct Metric: Equatable, Identifiable {
        var id: String { label }
        let label: String
        let value: String
        /// Out of range (dry air, short sleep, low HRV, a hot day).
        let flagged: Bool
    }

    let id: Int
    /// "LAST NIGHT · FRI OCT 23", "TUE OCT 20"
    let eyebrow: String
    let minutes: Int
    let hot: Bool
    /// "3.4× usual"
    let ratio: String
    let metrics: [Metric]
    let events: [TrendsEvent]
}

/// What the Trends tab shows, all from `StageStory` and its longer history `StageHistory`.
///
/// Nights are numbered like `StageStory`'s (0 = oldest of the 14 … 13 = last night). The 60 nights of
/// `StageHistory` before them have negative numbers (−60 … −1); "All time" shows all 74.
enum TrendsStory {
    static var calendar: Calendar { TodayStory.calendar }

    // MARK: Nights

    static var nightIDs: ClosedRange<Int> { StageHistory.nightIDs }
    static var nightCount: Int { nightIDs.count }

    static func night(_ i: Int) -> StageHistory.Night { StageHistory.night(i) }

    /// A day's high of 85 °F or more.
    static let hotFromF = 85
    /// HRV under this is "low" (stress): his usual is 52 ms.
    static let lowHrvBelow = 45

    /// Heart-rate variability on night `i`, ms: `StageStory.hrvMs` for the last 14 nights; before them a
    /// steady value around his usual with small deterministic night-to-night noise, a dip on the nights
    /// of the earlier flare (poor sleep) and after short nights.
    static func hrv(_ i: Int) -> Int {
        if i >= 0 { return StageStory.hrvMs[min(i, StageStory.hrvMs.count - 1)] }
        let flareDip: [Int: Int] = [-4: 4, -3: 7, -2: 8, -1: 5]
        let noise = ((i * 37 + 1_000_003) % 7) - 3
        let short = StageHistory.night(i).sleepHours < StageHistory.shortSleepBelow ? 3 : 0
        return StageStory.usualHrvMs + noise - (flareDip[i] ?? 0) - short
    }

    /// The exam weeks, oldest first (mid-September and the midterms).
    static var examRuns: [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for n in StageHistory.nights where n.exams {
            if let last = runs.last, last.upperBound == n.id - 1 {
                runs[runs.count - 1] = last.lowerBound...n.id
            } else {
                runs.append(n.id...n.id)
            }
        }
        return runs
    }

    // MARK: Chart

    /// Minutes at the top of the bars: a little above the worst night.
    static var scaleTop: Double { (Double(StageHistory.nights.map(\.minutes).max() ?? 1) * 1.1).rounded(.up) }

    /// The thin tracks under the bars, in order.
    static let tracks: [TimelineChart.Track] = [
        .init(name: "Sleep", unit: "hours", domain: 4.5...8.5, threshold: StageHistory.shortSleepBelow),
        .init(name: "Humidity", unit: "outdoor %", domain: 20...80, threshold: Double(StageStory.dryBelowPercent)),
        .init(name: "Temp", unit: "high °F", domain: 55...95, threshold: Double(hotFromF), flagBelow: false),
        .init(name: "Stress", unit: "HRV ms", domain: 30...64, threshold: Double(lowHrvBelow)),
    ]

    /// The event lanes; "New" takes a second row only while the sweater and the sample (same first
    /// night) are both on the chart.
    static func lanes(_ range: TrendsRange) -> [TimelineChart.Lane] {
        let rows = events(range).filter { $0.lane == 0 }.map(\.row).max().map { $0 + 1 } ?? 1
        return [
        .init(name: "New", unit: "items", rows: rows),
        .init(name: "Life", unit: "exams · gym", rows: 1),
        ]
    }

    static func nights(_ range: TrendsRange, now: Date = Date()) -> [TimelineChart.Night] {
        let cal = calendar
        return range.ids.map { i in
            let n = night(i)
            let date = StageStory.nightDate(i, now: now, calendar: cal)
            return TimelineChart.Night(
                id: i, minutes: Double(n.minutes), hot: n.flare,
                day: "\(cal.component(.day, from: date))",
                month: StageStory.month(date, calendar: cal).uppercased(),
                startsMonth: cal.component(.day, from: date) == 1,
                isLast: i == StageStory.lastNightIndex,
                values: [n.sleepHours, Double(n.humidity), Double(n.highF), Double(hrv(i))],
                accessibility: accessibility(i, date: date))
        }
    }

    /// The events on the chart's nights (clipped to the range).
    static func events(_ range: TrendsRange) -> [TimelineChart.Event] {
        guard let first = range.ids.first, let last = range.ids.last else { return [] }
        return TrendsEvent.all.compactMap { e in
            guard e.end >= first, e.start <= last else { return nil }
            let lane = e.isProduct ? 0 : 1
            let row = e.kind == .detergent ? 1 : 0
            return TimelineChart.Event(
                id: e.id, lane: lane, row: row, start: max(e.start, first), end: min(e.end, last), emoji: e.emoji,
                fill: e.isProduct ? Twin.Palette.pink : Twin.Palette.paper,
                span: e.isProduct ? Twin.Palette.pinkSoft : Twin.Palette.fillStrong,
                dot: e.kind == .gym,
                accessibility: "\(e.shortName). Opens details.")
        }
    }

    // MARK: The reading line

    /// One line over the chart: "Two flares: Oct 6–9 after the new sweater and detergent sample, and
    /// Oct 20–now after the new body wash. Weather, exams and sleep didn't line up."
    ///
    /// Flares are runs of orange nights on the chart. Each is tied to the new things bought in the few
    /// days before it began (a strong or possible link in `TrendsPurchase`), and dated from the day after
    /// the purchase; the factors with no link over all 74 nights are named after.
    static func reading(_ range: TrendsRange, now: Date = Date()) -> (lead: String, rest: String, ruledOut: String) {
        let cal = calendar
        let ids = range.ids
        var runs: [ClosedRange<Int>] = []
        for i in ids where night(i).flare {
            if let last = runs.last, last.upperBound == i - 1 { runs[runs.count - 1] = last.lowerBound...i } else { runs.append(i...i) }
        }
        let suspects: [(TrendsEvent.Kind, String)] = [(.sweater, "new sweater"), (.detergent, "detergent sample"),
                                                      (.bodywash, "new body wash")]
        let linked: [(bought: Int, name: String)] = suspects.compactMap { k, name in
            guard let p = TrendsPurchase(k), [.strong, .possible].contains(p.verdict) else { return nil }
            return (p.bought, name)
        }
        let phrases: [String] = runs.map { run in
            // Bought at most `TrendsPurchase.leadDays` days before the flare's first night.
            let with = linked.filter { run.lowerBound > $0.bought && run.lowerBound - $0.bought <= TrendsPurchase.leadDays }
            var start = run.lowerBound
            for f in with where ids.contains(f.bought + 1) { start = min(start, f.bought + 1) }
            let a = StageStory.nightDate(start, now: now, calendar: cal)
            let b = StageStory.nightDate(run.upperBound, now: now, calendar: cal)
            let when = run.upperBound == StageStory.lastNightIndex ? "\(StageStory.monthDay(a, calendar: cal))–now"
                : (start == run.upperBound ? StageStory.monthDay(a, calendar: cal) : StageStory.monthDayRange(a, b, calendar: cal))
            return with.isEmpty ? when : "\(when) after the \(joined(with.map(\.name)))"
        }
        let none: [(StageHistory.Factor, String)] = [(.dryAir, "Weather"), (.exams, "exams"), (.shortSleep, "sleep")]
            .filter { StageHistory.impact($0.0).verdict == .none }
        let ruledOut = none.isEmpty ? "" : "\(joined(none.map(\.1))) didn't line up."
        guard !runs.isEmpty else {
            return ("No flares:", "scratching stayed near your usual \(StageStory.usual) min.", ruledOut)
        }
        let count = ["One flare", "Two flares", "Three flares"][min(runs.count, 3) - 1]
        // Two long clauses read better with a comma before "and".
        let list = phrases.count == 2 ? phrases.joined(separator: ", and ") : joined(phrases)
        return ("\(count):", list + ".", ruledOut)
    }

    /// "a, b and c"
    static func joined(_ items: [String]) -> String {
        items.count <= 1 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    // MARK: The selected night

    static func detail(_ i: Int, now: Date = Date()) -> TrendsNight {
        let i = min(max(i, nightIDs.lowerBound), nightIDs.upperBound)
        let n = night(i)
        let date = StageStory.nightDate(i, now: now, calendar: calendar)
        let day = dayText(date).uppercased()
        let hrv = hrv(i)
        return TrendsNight(
            id: i,
            eyebrow: i == StageStory.lastNightIndex ? "LAST NIGHT · \(day)" : day,
            minutes: n.minutes, hot: n.flare,
            ratio: String(format: "%.1f× usual", Double(n.minutes) / Double(StageStory.usual)),
            metrics: [
                .init(label: "Sleep", value: String(format: "%.1f h", n.sleepHours), flagged: n.sleepHours < StageHistory.shortSleepBelow),
                .init(label: "Humidity", value: "\(n.humidity)%", flagged: n.dry),
                .init(label: "Temp", value: "\(n.highF)°F", flagged: n.highF >= hotFromF),
                .init(label: "HRV", value: "\(hrv) ms", flagged: hrv < lowHrvBelow),
            ],
            events: TrendsEvent.on(i))
    }

    /// "Tue Oct 20"
    static func dayText(_ date: Date) -> String {
        "\(StageStory.weekday(date, short: true, calendar: calendar)) \(StageStory.monthDay(date, calendar: calendar))"
    }

    /// "Tue Oct 20" for night `i`.
    static func dayText(night i: Int, now: Date = Date()) -> String {
        dayText(StageStory.nightDate(i, now: now, calendar: calendar))
    }

    /// "Tuesday, Oct 20: 17 minutes. Slept 6.9 hours, humidity 49%, high 66°F, HRV 51 ms. New body wash."
    private static func accessibility(_ i: Int, date: Date) -> String {
        let n = night(i)
        var text = "\(StageStory.weekday(date, calendar: calendar)), \(StageStory.monthDay(date, calendar: calendar)): "
            + "\(n.minutes) minutes"
        if i == StageStory.lastNightIndex { text = "Last night, " + text }
        text += n.flare ? ", above your usual." : "."
        text += String(format: " Slept %.1f hours, humidity %d%%, high %d°F, HRV %d ms.", n.sleepHours, n.humidity, n.highF, hrv(i))
        for e in TrendsEvent.on(i) { text += " \(e.shortName)." }
        return text
    }
}

// MARK: - Launch arguments (debug builds: screenshots)

enum TrendsLaunch {
    private static func string(_ key: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: key)
        #else
        return nil
        #endif
    }

    /// `-trendsScrollBack 9`: the scrolling chart moves back so the night 9 nights before last night
    /// sits at its right edge.
    static var scrollBack: Int? { string("trendsScrollBack").flatMap(Int.init) }
    /// `-trendsSelect -2`: selects that night after the entrance (read from the raw arguments: a
    /// negative number would look like a flag to `UserDefaults`).
    static var select: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let k = args.firstIndex(of: "-trendsSelect"), args.indices.contains(k + 1) else { return nil }
        return Int(args[k + 1])
        #else
        return nil
        #endif
    }
    /// `-trendsEvent bodywash|sweater|detergent|exams|gym`: opens that event's sheet.
    static var event: String? { string("trendsEvent") }
}

// MARK: - After a purchase

/// How scratching went right after he bought a new item, from what the app can read (the order date
/// and the nightly minutes; not when he used it): the average of the 4 nights after the order date
/// against his usual 12 min. Items bought the same day share those nights, so the data can't
/// separate them (the sweater and the detergent sample, Oct 5).
struct TrendsPurchase {
    /// Nights after the order date that are compared.
    static let nightsAfter = 4
    /// A flare that starts at most this many days after an order is read as "after" it.
    static let leadDays = 3

    let kind: TrendsEvent.Kind
    /// The night of the order date.
    let bought: Int
    /// The nights compared (up to 4, ending at last night at the latest).
    let nights: ClosedRange<Int>
    /// Average minutes on those nights.
    let afterMinutes: Double
    let usual: Int
    /// Other new items bought the same day.
    let sameDay: [TrendsEvent.Kind]

    init?(_ kind: TrendsEvent.Kind) {
        guard let b = TrendsEvent.purchaseNight(kind), b < StageStory.lastNightIndex else { return nil }
        self.kind = kind
        bought = b
        nights = (b + 1)...min(b + Self.nightsAfter, StageStory.lastNightIndex)
        afterMinutes = Double(nights.map { StageHistory.night($0).minutes }.reduce(0, +)) / Double(nights.count)
        usual = StageStory.usual
        sameDay = TrendsEvent.Kind.allCases.filter { $0 != kind && TrendsEvent.purchaseNight($0) == b }
    }

    /// after − usual, rounded.
    var difference: Int { Int((afterMinutes - Double(usual)).rounded()) }

    /// 5+ min above usual: strong (possible when another new item was bought the same day); 1.5–5: weak.
    var verdict: StageHistory.Verdict {
        let d = afterMinutes - Double(usual)
        if d >= StageHistory.strongLinkMinutes { return sameDay.isEmpty ? .strong : .possible }
        if d >= StageHistory.weakLinkMinutes { return .weak }
        return .none
    }
}
