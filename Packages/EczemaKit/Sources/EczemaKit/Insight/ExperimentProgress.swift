import Foundation

/// Where the running test stands, computed from the dataset (no hard-coded numbers in the UI).
///
/// "During" averages only full days (today is not over yet, so it would look better than it is);
/// on day 1 there is no full day yet and `during` is nil.
public struct ExperimentProgress: Hashable, Sendable {
    public var experiment: Experiment
    /// Day of the test, 1...length.
    public var day: Int
    public var length: Int
    /// Mean scratch minutes per day before the test.
    public var before: Double
    /// Mean scratch minutes per day of the full test days so far.
    public var during: Double?
    /// Number of full days in `during`.
    public var fullDays: Int
    /// One slot per test day: minutes for days so far (today included, partial), nil for the days to come.
    public var perDay: [Double?]
    /// The person's usual minutes per day.
    public var usual: Double
    /// Mean indoor humidity during the test days, and on the flare days before it.
    public var humidityDuring: Double?
    public var humidityBefore: Double?
    /// Other suspects from the case file that were still around on most test days (e.g. the dry air).
    public var stillPresent: [Suspect]

    public var status: ExperimentStatus { experiment.status }
    public var isFinished: Bool { experiment.status != .running }
    public var daysLeft: Int { max(0, length - day) }
    public var progress: Double { length > 0 ? Double(day) / Double(length) : 0 }
    /// during ÷ before − 1 (−0.3 = 30% less). nil before the first full day.
    public var change: Double? {
        guard let during, before > 0 else { return nil }
        return during / before - 1
    }
    /// Whole percent less (positive) or more (negative) than before.
    public var percentLess: Int? { change.map { Int((-$0 * 100).rounded()) } }
    public var startDay: Date { experiment.startDay }

    public init?(dataset: TwinDataset, calendar: Calendar = .current) {
        guard let e = dataset.experiment else { return nil }
        experiment = e
        length = max(e.plan.lengthDays, 1)
        let testDays = Array(dataset.experimentDays(calendar: calendar).prefix(length))
        day = min(max(testDays.count, 1), length)
        before = e.baselineMinutesPerDay
        usual = dataset.baselineMinutesPerDay

        let todayStart = calendar.startOfDay(for: dataset.today?.day ?? Date())
        let full = testDays.filter { calendar.startOfDay(for: $0.day) < todayStart }
        fullDays = full.count
        during = StatsEngine.mean(full.map(\.scratchMinutes))
        perDay = (0..<length).map { i in i < testDays.count ? testDays[i].scratchMinutes : nil }

        humidityDuring = StatsEngine.mean(testDays.map(\.humidityPct))
        let start = calendar.startOfDay(for: e.startDay)
        let beforeDays = dataset.days.filter { $0.day < start }.suffix(7)
        humidityBefore = StatsEngine.mean(beforeDays.map(\.humidityPct))

        // Which other suspects stayed around while the test ran (the reason a drop is convincing).
        var others: [Suspect] = []
        for s in dataset.caseFile?.suspects ?? [] where s.kind != nil && s.kind != e.plan.trigger {
            let present = testDays.filter { d in d.exposures.contains { $0.kind == s.kind } }.count
            if !testDays.isEmpty, Double(present) / Double(testDays.count) >= 0.7 { others.append(s) }
        }
        stillPresent = others
    }
}

extension ExperimentPlan {
    /// The thing being changed: "Pause the body wash" → "body wash", "Stop dairy" → "dairy".
    public var subject: String? {
        let verbs = ["pause", "stop", "skip", "avoid", "remove", "cut", "drop", "quit", "switch off", "leave out", "go without"]
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        guard let verb = verbs.first(where: { lower.hasPrefix($0 + " ") }) else { return nil }
        t = String(t.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        for article in ["the ", "your ", "my ", "all ", "any "] where t.lowercased().hasPrefix(article) {
            t = String(t.dropFirst(article.count))
        }
        if let r = t.range(of: " for ") { t = String(t[..<r.lowerBound]) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return t.isEmpty ? nil : t.lowercased()
    }

    /// One word for small labels: "body wash" → "wash".
    public var shortSubject: String? { subject?.split(separator: " ").last.map(String.init) }
}
