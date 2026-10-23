import SwiftUI
import EczemaKit

/// Data helpers for the Today and Trends tabs. Everything is derived from `app.dataset`
/// (no hard-coded numbers or dates). A namespace so names never clash with other areas.
enum TodayTrends {

    // MARK: Usual values

    /// Days that look like the user's normal (within 25% of the usual minutes), today excluded.
    static func calmDays(in ds: TwinDataset) -> [DayRecord] {
        let past = Array(ds.days.dropLast())
        let usual = ds.baselineMinutesPerDay
        guard usual > 0 else { return past }
        let calm = past.filter { $0.scratchMinutes <= usual * 1.25 }
        return calm.isEmpty ? past : calm
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    static func usualSleep(in ds: TwinDataset) -> Double? { median(calmDays(in: ds).map(\.sleepHours)) }
    static func usualHRV(in ds: TwinDataset) -> Double? { median(calmDays(in: ds).map(\.hrvMs)) }

    /// Flare day: at least 1.5× the usual minutes (the stats engine's anomaly threshold).
    static func isFlare(_ minutes: Double, usual: Double) -> Bool {
        usual > 0 && minutes >= usual * 1.5
    }

    // MARK: A day compared with the usual

    enum Level { case calmer, usual, above }

    /// "At usual" is a ±25% band around the usual minutes.
    static func level(ratio: Double) -> Level {
        ratio > 1.25 ? .above : (ratio < 0.75 ? .calmer : .usual)
    }

    // MARK: When scratching happened

    /// The worst hours of a day: hours with at least 55% of the busiest hour, and the run of such
    /// hours around the busiest one ("Mostly at night, 1–5 am").
    struct HourPattern {
        var hot: Set<Int> = []
        var peak: ClosedRange<Int>?
        var share: Double = 0

        init(minutes: [Double]) {
            guard let maxV = minutes.max(), maxV >= 0.5, let worst = minutes.firstIndex(of: maxV) else { return }
            let threshold = maxV * 0.55
            hot = Set(minutes.indices.filter { minutes[$0] >= threshold })
            var lo = worst, hi = worst
            while lo > 0, hot.contains(lo - 1) { lo -= 1 }
            while hi < minutes.count - 1, hot.contains(hi + 1) { hi += 1 }
            peak = lo...hi
            let total = minutes.reduce(0, +)
            share = total > 0 ? minutes[lo...hi].reduce(0, +) / total : 0
        }

        /// ("Mostly at night", "1–5 am")
        var phrase: (lead: String, range: String)? {
            guard let peak else { return nil }
            let mid = (peak.lowerBound + peak.upperBound + 1) / 2
            let part: String = switch mid {
            case 0..<5: "at night"
            case 5..<12: "in the morning"
            case 12..<17: "in the afternoon"
            case 17..<21: "in the evening"
            default: "at night"
            }
            return ("\(share >= 0.45 ? "Mostly" : "Worst") \(part)", Format.hourRange(peak.lowerBound, peak.upperBound + 1))
        }
    }

    // MARK: Formatting

    enum Format {
        static func h12(_ h: Int) -> Int { let x = h % 12; return x == 0 ? 12 : x }
        static func meridiem(_ h: Int) -> String { (h % 24) < 12 ? "am" : "pm" }
        /// "3 am"
        static func hour(_ h: Int) -> String { "\(h12(h)) \(meridiem(h))" }
        /// "1–5 am", "11 pm–2 am". `end` is the hour the range ends at.
        static func hourRange(_ start: Int, _ end: Int) -> String {
            let s = start % 24, e = end % 24
            if meridiem(s) == meridiem(e), e > s { return "\(h12(s))–\(h12(e)) \(meridiem(e))" }
            return "\(hour(s))–\(hour(e))"
        }
        /// "Oct 18"
        static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
        /// "Fri"
        static func weekday(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated)) }
        /// "FRI · OCT 23"
        static func weekdayDay(_ d: Date) -> String { "\(weekday(d)) · \(day(d))".uppercased() }
        /// "Oct 20–21", "Oct 30–Nov 2"
        static func dayRange(_ a: Date, _ b: Date, calendar: Calendar = .current) -> String {
            if calendar.isDate(a, inSameDayAs: b) { return day(a) }
            if calendar.isDate(a, equalTo: b, toGranularity: .month) {
                return "\(day(a))–\(b.formatted(.dateTime.day()))"
            }
            return "\(day(a))–\(day(b))"
        }
        /// "2:14 am"
        static func clock(_ d: Date) -> String {
            d.formatted(.dateTime.hour().minute())
                .replacingOccurrences(of: "\u{202F}", with: " ")
                .lowercased()
        }
        /// "1 min 12 s", "48 s"
        static func duration(_ seconds: TimeInterval) -> String {
            let s = max(0, Int(seconds.rounded()))
            if s < 60 { return "\(s) s" }
            let m = s / 60, r = s % 60
            return r == 0 ? "\(m) min" : "\(m) min \(r) s"
        }
        /// "52°F" / "11°C" following the phone's measurement system.
        static func temperature(_ celsius: Double, locale: Locale = .current) -> String {
            if locale.measurementSystem == .us {
                return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
            }
            return "\(Int(celsius.rounded()))°C"
        }
        /// "1 episode", "3 episodes".
        static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
            "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
        }
    }
}

// MARK: - Today

/// Everything the Today tab shows, computed once per render from the dataset.
struct TodaySnapshot {
    let dataset: TwinDataset
    let day: DayRecord
    let now: Date
    let isToday: Bool
    let minutes: Double
    let usual: Double
    let ratio: Double
    let level: TodayTrends.Level
    let pattern: TodayTrends.HourPattern
    /// Today's episodes, oldest first, none in the future.
    let episodes: [ScratchEpisode]
    let episodeCount: Int
    let intenseCount: Int
    let usualSleep: Double?
    let usualHRV: Double?
    /// Hours since midnight when the last day is today.
    let nowHour: Double?

    init?(dataset ds: TwinDataset, now: Date = Date(), calendar cal: Calendar = .current) {
        guard let day = ds.today else { return nil }
        dataset = ds
        self.day = day
        self.now = now
        isToday = cal.isDate(day.day, inSameDayAs: now)
        minutes = day.scratchMinutes
        usual = ds.baselineMinutesPerDay
        ratio = usual > 0 ? minutes / usual : 1
        level = TodayTrends.level(ratio: ratio)
        pattern = TodayTrends.HourPattern(minutes: day.scratchMinutesByHour)
        let mine = ds.episodes
            .filter { cal.isDate($0.start, inSameDayAs: day.day) && $0.start <= now && $0.label != .rejected }
            .sorted { $0.start < $1.start }
        episodes = mine
        episodeCount = mine.isEmpty ? day.episodeCount : mine.count
        intenseCount = mine.isEmpty ? day.intenseCount : mine.filter(\.intense).count
        usualSleep = TodayTrends.usualSleep(in: ds)
        usualHRV = TodayTrends.usualHRV(in: ds)
        nowHour = isToday ? now.timeIntervalSince(cal.startOfDay(for: now)) / 3600 : nil
    }

    /// Ring progress: today ÷ (3 × usual).
    var ringProgress: Double { usual > 0 ? minutes / (3 * usual) : 0 }
    var accent: Color { level == .above ? Twin.Palette.orange : Twin.Palette.lime }
    /// Hour-chart scale: the busiest hour, but never less than a calm day's busiest hour × ~3,
    /// so a calm day looks calm.
    var hourScaleMax: Double { max(day.scratchMinutesByHour.max() ?? 0, usual * 0.3) }

    /// Last `n` days of a value (oldest first, today last).
    func recent(_ n: Int, _ value: (DayRecord) -> Double) -> [Double] {
        dataset.days.suffix(n).map(value)
    }

    /// Exposures the user logged today (not detected automatically).
    var loggedToday: [Exposure] { day.exposures.filter { !$0.automatic } }
    /// Automatic exposures other than the weather ones shown as stickers (e.g. a workout).
    var autoToday: [Exposure] { day.exposures.filter { $0.automatic && $0.kind != .dryAir } }
}
