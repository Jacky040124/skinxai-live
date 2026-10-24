import Foundation
import EczemaKit

/// Everything the doctor report shows, computed from the dataset (no hard-coded numbers).
struct ReportFacts {
    struct Bar: Identifiable {
        let id: Int
        let day: Date
        let minutes: Double
        let flare: Bool
        let inTest: Bool
        let marker: String?       // emoji of an exposure that started that day
        let markerTint: MarkerTint
    }
    enum MarkerTint { case pink, orange, paper }

    struct Change: Identifiable {
        let id: String
        let emoji: String
        let title: String
        let from: Date
        let to: Date
        let ongoing: Bool
        let automatic: Bool
    }

    struct Vital {
        let label: String
        let recent: String
        let usual: String
        /// ▲ / ▼ when clearly different from the calm days.
        let arrow: String?
        let worse: Bool
    }

    let name: String
    let generated: Date
    let windowStart: Date
    let windowEnd: Date
    let dayCount: Int
    let isDemo: Bool

    let todayMinutes: Double
    let todayRatio: Double
    let usual: Double
    /// Full days the watch tracked (real mode can have few).
    let trackedDays: Int
    let weekAverage: Double
    let previousWeekAverage: Double?
    let worstHours: String?
    let flareStart: Date?
    let totalEpisodes: Int
    let intenseEpisodes: Int

    let bars: [Bar]
    let changes: [Change]
    let vitals: [Vital]

    let caseFile: CaseFile?
    let experiment: Experiment?
    let experimentDay: Int
    let experimentAfter: Double?

    /// "Your usual" is only the starting estimate until the watch has tracked 3 full days.
    var usualIsEstimate: Bool { trackedDays < 3 }

    var weekChange: Double? {
        guard let prev = previousWeekAverage, prev > 0 else { return nil }
        return (weekAverage - prev) / prev
    }

    var experimentChange: Double? {
        guard let e = experiment, let after = experimentAfter, e.baselineMinutesPerDay > 0 else { return nil }
        return (after - e.baselineMinutesPerDay) / e.baselineMinutesPerDay
    }

    init(dataset d: TwinDataset, name: String, now: Date = Date(), calendar: Calendar = .current) {
        self.name = name
        generated = now
        isDemo = d.isDemo
        let days = d.days
        let firstDay = days.first?.day ?? calendar.startOfDay(for: now)
        let lastDay = days.last?.day ?? calendar.startOfDay(for: now)
        let baseline = max(0.1, d.baselineMinutesPerDay)
        windowStart = firstDay
        windowEnd = lastDay
        dayCount = days.count
        usual = baseline
        trackedDays = days.dropLast().filter { $0.episodeCount > 0 }.count
        todayMinutes = d.today?.scratchMinutes ?? 0
        todayRatio = d.todayRatio

        let minutes = days.map(\.scratchMinutes)
        let last7 = minutes.suffix(7)
        weekAverage = last7.isEmpty ? 0 : last7.reduce(0, +) / Double(last7.count)
        let prev7 = minutes.dropLast(7).suffix(7)
        let prevAverage = prev7.isEmpty ? 0 : prev7.reduce(0, +) / Double(prev7.count)
        previousWeekAverage = prevAverage > 0 ? prevAverage : nil

        // Worst hours of the last week: the run of hours with at least 55% of the busiest hour,
        // around it. The same rule as Today's "Mostly at night, 1–5 am", so both say the same.
        var byHour = [Double](repeating: 0, count: 24)
        for day in days.suffix(7) { for h in 0..<24 { byHour[h] += day.scratchMinutesByHour[h] } }
        if let peak = byHour.max(), peak >= 0.5, let worst = byHour.firstIndex(of: peak) {
            let hot = byHour.map { $0 >= peak * 0.55 }
            var lo = worst, hi = worst
            while lo > 0, hot[lo - 1] { lo -= 1 }
            while hi < 23, hot[hi + 1] { hi += 1 }
            worstHours = Self.hourRange(lo, hi + 1)
        } else {
            worstHours = nil
        }

        let limit = 1.5 * baseline
        var start: Date?
        for i in 0..<max(0, days.count - 1) where days[i].scratchMinutes > limit && days[i + 1].scratchMinutes > limit {
            start = days[i].day
            break
        }
        flareStart = start
        totalEpisodes = days.suffix(7).reduce(0) { $0 + $1.episodeCount }
        intenseEpisodes = days.suffix(7).reduce(0) { $0 + $1.intenseCount }

        // What changed: exposures that ran 2+ days in a row or are new products, by first day.
        var runs: [String: (kind: ExposureKind, first: Date, last: Date, count: Int, automatic: Bool)] = [:]
        for day in days {
            for e in day.exposures {
                if var r = runs[e.title] {
                    r.last = day.day
                    r.count += 1
                    runs[e.title] = r
                } else {
                    runs[e.title] = (e.kind, day.day, day.day, 1, e.automatic)
                }
            }
        }
        let interesting = runs.filter { title, r in
            let span = (calendar.dateComponents([.day], from: r.first, to: r.last).day ?? 0) + 1
            let consecutive = r.count >= 2 && span == r.count
            return consecutive || r.kind == .newProduct || r.kind == .detergent
        }
        let changeList: [Change] = interesting.map { title, r in
            Change(id: title, emoji: r.kind.emoji, title: title, from: r.first, to: r.last,
                   ongoing: calendar.isDate(r.last, inSameDayAs: lastDay), automatic: r.automatic)
        }
        .sorted { $0.from < $1.from }
        .prefix(4)
        .map { $0 }
        changes = changeList

        // Bars, with a marker where a change started.
        let testStart = d.experiment.map { calendar.startOfDay(for: $0.startDay) }
        bars = days.enumerated().map { i, day in
            let started = changeList.first { calendar.isDate($0.from, inSameDayAs: day.day) && !calendar.isDate($0.from, inSameDayAs: firstDay) }
            let tint: MarkerTint = started.map { $0.automatic ? .orange : .pink } ?? .paper
            return Bar(id: i, day: day.day, minutes: day.scratchMinutes, flare: day.scratchMinutes > limit,
                       inTest: testStart.map { day.day >= $0 } ?? false, marker: started?.emoji, markerTint: tint)
        }

        // Sleep & stress: last 7 days vs. the calm days before the flare.
        let calmDays = days.prefix { $0.scratchMinutes <= limit }
        let recentDays = Array(days.suffix(7))
        func avg(_ xs: [Double]) -> Double? { let v = xs.filter { $0 > 0 }; return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        func pair(_ label: String, _ key: (DayRecord) -> Double, digits: Int, unit: String, worseIfLower: Bool) -> Vital? {
            guard let r = avg(recentDays.map(key)) else { return nil }
            let c = avg(calmDays.map(key))
            let fmt: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(digits))) + unit }
            let lower = c.map { r < $0 * 0.95 } ?? false
            let higher = c.map { r > $0 * 1.05 } ?? false
            let worse = worseIfLower ? lower : higher
            return Vital(label: label, recent: fmt(r), usual: c.map(fmt) ?? "—",
                         arrow: lower ? "▼" : (higher ? "▲" : nil), worse: worse)
        }
        vitals = [
            pair("Sleep", { $0.sleepHours }, digits: 1, unit: " h", worseIfLower: true),
            pair("Wake-ups / night", { Double($0.wakeUps) }, digits: 1, unit: "", worseIfLower: false),
            pair("HRV", { $0.hrvMs }, digits: 0, unit: " ms", worseIfLower: true),
            pair("Resting HR", { $0.restingHR }, digits: 0, unit: " bpm", worseIfLower: false),
        ].compactMap { $0 }

        caseFile = d.caseFile
        experiment = d.experiment
        let expDays = d.experimentDays(calendar: calendar)
        experimentDay = expDays.count
        experimentAfter = expDays.isEmpty ? nil : expDays.map(\.scratchMinutes).reduce(0, +) / Double(expDays.count)
    }

    /// "2–4 am", "11 pm–1 am".
    static func hourRange(_ from: Int, _ to: Int) -> String {
        func h(_ x: Int) -> (Int, String) {
            let v = ((x % 24) + 24) % 24
            return (v % 12 == 0 ? 12 : v % 12, v < 12 ? "am" : "pm")
        }
        let a = h(from), b = h(to)
        return a.1 == b.1 ? "\(a.0)–\(b.0) \(b.1)" : "\(a.0) \(a.1)–\(b.0) \(b.1)"
    }
}
