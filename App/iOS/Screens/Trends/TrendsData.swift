import SwiftUI
import EczemaKit

/// Chart range of the Trends tab.
enum TrendsRange: String, CaseIterable, Identifiable, Hashable {
    case week, twoWeeks, all
    var id: Self { self }
    var title: String {
        switch self { case .week: "7 days"; case .twoWeeks: "14 days"; case .all: "All" }
    }
    func dayCount(total: Int) -> Int {
        switch self { case .week: min(7, total); case .twoWeeks: min(14, total); case .all: total }
    }
}

/// Something that changed during the story: an exposure that started after the first day and
/// lasted at least two days in a row, or the user's test. One-off things (a dairy day, a workout)
/// are "also logged" instead.
struct TrendsChange: Identifiable {
    let id: String
    let kind: ExposureKind?
    let emoji: String
    let title: String
    /// Marker text on the chart, e.g. "new wash".
    let short: String
    let startIndex: Int
    let endIndex: Int
    let ongoing: Bool
    let detail: String
    let fill: Color
    /// The user's test paused this one.
    let paused: Bool
    let isTest: Bool
}

struct TrendsRoutine: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let count: Int
}

/// Everything the Trends tab shows, derived from the dataset.
struct TrendsSnapshot {
    let dataset: TwinDataset
    let range: TrendsRange
    let days: [DayRecord]
    let visibleStart: Int
    let usual: Double
    /// "Your usual" is only the starting estimate (real data, fewer than 3 tracked days).
    let usualIsEstimate: Bool
    /// Average minutes per tracked day over the last 7 days; nil when the watch tracked none.
    let thisWeek: Double?
    let lastWeek: Double?
    /// Whether the watch tracked each day (always true in the demo).
    let tracked: [Bool]
    let tones: [DailyScratchChart.Tone]
    let changes: [TrendsChange]
    let routine: [TrendsRoutine]
    let usualSleep: Double?
    let usualHRV: Double?

    init(dataset ds: TwinDataset, range: TrendsRange, calendar: Calendar = .current) {
        dataset = ds
        self.range = range
        days = ds.days
        let n = ds.days.count
        visibleStart = max(0, n - range.dayCount(total: n))
        usual = ds.baselineMinutesPerDay
        usualIsEstimate = TodayTrends.usualIsEstimate(in: ds)

        // Week averages count only days the watch tracked: in real data a day without episodes
        // may be a day the watch stayed on the charger, and must not pull the average down.
        let minutes = ds.days.map(\.scratchMinutes)
        let tracked = ds.days.map { TodayTrends.isTracked($0, in: ds) }
        self.tracked = tracked
        func average(_ indices: [Int]) -> Double? {
            let kept = indices.filter { tracked[$0] }
            return kept.isEmpty ? nil : kept.reduce(0) { $0 + minutes[$1] } / Double(kept.count)
        }
        let recent = Array(ds.days.indices.suffix(7))
        thisWeek = average(recent)
        let previous = Array(ds.days.indices.dropLast(7).suffix(7))
        lastWeek = previous.filter { tracked[$0] }.count >= 3 ? average(previous) : nil

        var seenFlare = false
        var t: [DailyScratchChart.Tone] = []
        for (i, m) in minutes.enumerated() {
            if TodayTrends.isFlare(m, usual: ds.baselineMinutesPerDay) { t.append(.flare); seenFlare = true }
            else { t.append(seenFlare && tracked[i] ? .improving : .normal) }
        }
        tones = t

        let found = Self.findChanges(in: ds, visibleStart: visibleStart, calendar: calendar)
        changes = found.0
        routine = found.1
        usualSleep = TodayTrends.usualSleep(in: ds)
        usualHRV = TodayTrends.usualHRV(in: ds)
    }

    var visible: ArraySlice<DayRecord> { days[visibleStart...] }
    var visibleRange: Range<Int> { visibleStart..<days.count }

    /// Week-over-week change as a fraction (1.56 = +156%), nil without a previous week.
    var weekChange: Double? {
        guard let thisWeek, let lastWeek, lastWeek > 0 else { return nil }
        return thisWeek / lastWeek - 1
    }

    /// Legend name of the dashed usual line on the chart.
    var usualLabel: String { usualIsEstimate ? "usual · starting estimate" : "your usual" }

    var subtitle: String {
        switch range {
        case .week: "Last \(range.dayCount(total: days.count)) days"
        case .twoWeeks: "Last \(range.dayCount(total: days.count)) days"
        case .all: "All \(days.count) days"
        }
    }

    func bars(calendar: Calendar = .current) -> [DailyScratchChart.Bar] {
        let compact = range == .week
        // Month captions where the range starts and where a new month begins; the first one is
        // dropped when a new month begins right after it (they would run into each other).
        var months = Set(visibleRange.filter { calendar.component(.day, from: days[$0].day) == 1 })
        if let next = months.min(), next - visibleStart < 3 {} else { months.insert(visibleStart) }
        return visibleRange.map { i in
            let d = days[i]
            // Weekday over each day for 7 days; otherwise the month captions above.
            let caption: String? = compact
                ? TodayTrends.Format.weekday(d.day).uppercased()
                : months.contains(i) ? d.day.formatted(.dateTime.month(.abbreviated)).uppercased() : nil
            let m = Int(d.scratchMinutes.rounded())
            let toneText: String = switch tones[i] {
            case .flare: "flare day"
            case .improving: "improving"
            case .normal: tracked[i] ? "normal day" : "no episodes"
            }
            return DailyScratchChart.Bar(
                id: d.day, value: d.scratchMinutes, tone: tones[i],
                label: d.day.formatted(.dateTime.day()),
                caption: caption,
                isToday: i == days.count - 1,
                accessibility: "\(TodayTrends.Format.day(d.day)), \(m) minutes, \(toneText)")
        }
    }

    var markers: [DailyScratchChart.Marker] {
        changes.filter { visibleRange.contains($0.startIndex) }.map {
            DailyScratchChart.Marker(id: $0.id, barID: days[$0.startIndex].day, emoji: $0.emoji, text: $0.short, fill: $0.fill)
        }
    }

    func index(of date: Date?, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        return days.firstIndex { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// The smallest range that shows day `i`.
    func rangeShowing(_ i: Int) -> TrendsRange {
        let fromEnd = days.count - i
        if fromEnd <= TrendsRange.week.dayCount(total: days.count) { return .week }
        if fromEnd <= TrendsRange.twoWeeks.dayCount(total: days.count) { return .twoWeeks }
        return .all
    }

    // MARK: What changed

    static func findChanges(in ds: TwinDataset, visibleStart: Int, calendar: Calendar) -> ([TrendsChange], [TrendsRoutine]) {
        struct Group { var exposure: Exposure; var indices: [Int] }
        var groups: [String: Group] = [:]
        var order: [String] = []
        for (i, d) in ds.days.enumerated() {
            for e in d.exposures {
                let key = "\(e.kind.rawValue)|\(e.title)"
                if groups[key] == nil { groups[key] = Group(exposure: e, indices: []); order.append(key) }
                if groups[key]?.indices.last != i { groups[key]?.indices.append(i) }
            }
        }
        let suspects = ds.caseFile?.suspects ?? []
        let last = ds.days.count - 1
        var changes: [TrendsChange] = []
        var routine: [TrendsRoutine] = []

        for key in order {
            guard let g = groups[key] else { continue }
            let e = g.exposure
            // First run of 2+ consecutive days that starts after the first day.
            var runStart: Int?
            var k = 0
            while k < g.indices.count {
                var j = k
                while j + 1 < g.indices.count, g.indices[j + 1] == g.indices[j] + 1 { j += 1 }
                if j > k, g.indices[k] > 0 { runStart = g.indices[k]; break }
                k = j + 1
            }
            guard let start = runStart else {
                let n = g.indices.filter { $0 >= visibleStart }.count
                if n > 0 { routine.append(TrendsRoutine(id: key, emoji: e.kind.emoji, title: e.title, count: n)) }
                continue
            }
            let end = g.indices.last ?? start
            let isTop = suspects.first?.kind == e.kind
            let suspect = suspects.first { $0.kind == e.kind }
            let fill: Color = isTop ? Twin.Palette.pink
                : (suspect.map { $0.confidence != .low } ?? false) ? Twin.Palette.orange : Twin.Palette.paper
            let paused = ds.experiment?.plan.trigger == e.kind && end < last
            var detail: String
            if e.kind == .dryAir {
                let hums = ds.days[start...end].map(\.humidityPct)
                detail = "auto · humidity \(Int(hums.min() ?? 0))–\(Int(hums.max() ?? 0))%"
            } else {
                detail = e.automatic ? "detected automatically" : "you logged it"
            }
            if isTop { detail += " · Claude's top suspect" }
            changes.append(TrendsChange(id: key, kind: e.kind, emoji: e.kind.emoji, title: e.title,
                                        short: shortLabel(e), startIndex: start, endIndex: end, ongoing: end == last,
                                        detail: detail, fill: fill, paused: paused, isTest: false))
        }

        if let test = ds.experiment, let start = ds.days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: test.startDay) }) {
            let dayN = min(ds.days.count - start, test.plan.lengthDays)
            let status: String = switch test.status {
            case .running: "day \(dayN) of \(test.plan.lengthDays)"
            case .confirmed: "done · confirmed"
            case .notConfirmed: "done · not confirmed"
            case .stopped: "stopped"
            }
            changes.append(TrendsChange(id: "test", kind: test.plan.trigger, emoji: "🧪", title: test.plan.title,
                                        short: "test", startIndex: start, endIndex: last, ongoing: test.status == .running,
                                        detail: "\(test.plan.lengthDays)-day test · \(status)", fill: Twin.Palette.cyan,
                                        paused: false, isTest: true))
        }
        changes.sort { $0.startIndex < $1.startIndex }
        routine.sort { $0.count > $1.count }
        return (changes, routine)
    }

    /// "New scented body wash" → "new wash", "Dry air" → "dry air".
    static func shortLabel(_ e: Exposure) -> String {
        let words = e.title.split(separator: " ").map { $0.lowercased() }
        if words.count <= 2 { return words.joined(separator: " ") }
        if words.first == "new", let last = words.last { return "new \(last)" }
        return words.suffix(2).joined(separator: " ")
    }
}
