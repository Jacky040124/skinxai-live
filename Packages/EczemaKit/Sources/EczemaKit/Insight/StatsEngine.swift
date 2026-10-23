import Foundation

// MARK: - Result

/// The numbers the app computes before Claude explains them ("stats first, then the model explains").
public struct InsightStats: Codable, Hashable, Sendable {

    /// A run of at least `StatsEngine.minFlareDays` days in a row above the flare threshold.
    public struct Flare: Codable, Hashable, Sendable {
        public var startIndex: Int
        public var endIndex: Int            // inclusive
        public var start: Date
        public var end: Date
        public var meanMinutes: Double
        public var peakMinutes: Double
        public var peakDay: Date
        public var days: Int { endIndex - startIndex + 1 }
    }

    /// When an exposure first showed up, relative to the most recent flare.
    public enum Onset: String, Codable, Hashable, Sendable {
        /// Started 0–3 days before the flare began: fits the usual 1–3 day lag.
        case beforeFlare
        /// Started more than 3 days before the flare began.
        case longBefore
        /// Started after the flare had begun: it can make a flare worse but cannot have started it.
        case afterFlareStart
        /// There is no flare in the window.
        case noFlare
    }

    public struct ExposureStat: Codable, Hashable, Sendable, Identifiable {
        /// "kind:lowercased title", e.g. "newProduct:new scented body wash".
        public var id: String
        public var kind: ExposureKind
        public var title: String
        public var automatic: Bool
        /// Indices into `InsightStats.minutes` of the days it was present.
        public var dayIndices: [Int]
        public var firstDay: Date
        public var lastDay: Date
        /// Mean scratch minutes on the 1–3 days after any day with the exposure.
        public var meanAfter: Double?
        /// Mean scratch minutes on every other day.
        public var meanOther: Double?
        /// meanAfter ÷ meanOther (1 = no difference).
        public var effectRatio: Double?
        /// Lag (0–3 days) with the strongest effect, and that effect.
        public var bestLag: Int?
        public var bestLagRatio: Double?
        public var onset: Onset
        /// Days from the first exposure to the start of the flare (only when it started before it).
        public var leadDays: Int?
        public var presentOnLastDay: Bool
        /// Ordering score (effect, adjusted for timing and amount of evidence). Higher = more suspicious.
        public var score: Double

        public var daysPresent: Int { dayIndices.count }
        /// Started 0–3 days before the flare, or clearly raises scratching.
        public var isCandidate: Bool { onset == .beforeFlare || (effectRatio ?? 0) >= StatsEngine.candidateRatio }
    }

    public var windowStart: Date
    public var windowEnd: Date
    /// Scratch minutes per day, oldest first (the last day may be partial).
    public var minutes: [Double]
    /// The person's usual minutes per day (median of calm days).
    public var baselineMinutes: Double
    /// Days above this count towards a flare (1.5 × baseline).
    public var thresholdMinutes: Double
    /// Flares in the window, oldest first.
    public var flares: [Flare]
    /// Exposures, most suspicious first.
    public var exposures: [ExposureStat]
    /// Groups of exposure ids that started together and were (almost) always present together,
    /// so this log can't tell them apart yet.
    public var cannotSeparate: [[String]]

    public var dayCount: Int { minutes.count }
    /// The most recent flare.
    public var currentFlare: Flare? { flares.last }
    public func exposure(id: String) -> ExposureStat? { exposures.first { $0.id == id } }
    /// The most suspicious exposure of that kind.
    public func exposure(kind: ExposureKind) -> ExposureStat? { exposures.first { $0.kind == kind } }
    /// Exposure ids that can't be separated from `id`.
    public func confounded(with id: String) -> [String] {
        cannotSeparate.first { $0.contains(id) }?.filter { $0 != id } ?? []
    }
}

// MARK: - Engine

/// Baseline, flare (anomaly) detection, per-exposure lagged effect and can't-separate detection.
///
/// - Baseline: median of calm days. Calm days are found robustly: the median of the lower half of all
///   days gives a first guess, and every day at or below 1.5 × that guess counts as calm.
/// - Flare (anomaly): at least 2 days in a row above 1.5 × baseline.
/// - Lagged effect per exposure: mean minutes on the 1–3 days after it vs. all other days, the ratio, and
///   the single lag (0–3 days) where the difference is largest.
/// - Can't separate: two candidate exposures that started on the same or adjacent day and were present
///   on nearly the same days (they differ on fewer than 3 days).
public enum StatsEngine {
    public static let flareFactor = 1.5
    /// A flare day must also be at least this many minutes above the baseline (guards tiny baselines).
    public static let minimumFlareExcess = 2.0
    public static let minFlareDays = 2
    public static let lagWindow = 1...3
    public static let candidateRatio = 1.3
    /// Two exposures need to differ on at least this many days before the log can tell them apart.
    public static let separatingDays = 3

    // MARK: Building blocks

    public static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The usual minutes per day: the median of calm days.
    public static func baseline(_ minutes: [Double]) -> Double {
        let sorted = minutes.sorted()
        guard !sorted.isEmpty else { return 0 }
        let lowerHalf = Array(sorted.prefix(max(1, (sorted.count + 1) / 2)))
        let guess = median(lowerHalf)
        let calm = sorted.filter { $0 <= guess * flareFactor }
        return median(calm.isEmpty ? lowerHalf : calm)
    }

    public static func threshold(baseline: Double) -> Double {
        max(baseline * flareFactor, baseline + minimumFlareExcess)
    }

    /// Index ranges of runs of `minFlareDays`+ days in a row above `threshold`.
    public static func flareRuns(_ minutes: [Double], threshold: Double) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for (i, m) in minutes.enumerated() {
            if m > threshold {
                if start == nil { start = i }
            } else if let s = start {
                if i - s >= minFlareDays { runs.append(s...(i - 1)) }
                start = nil
            }
        }
        if let s = start, minutes.count - s >= minFlareDays { runs.append(s...(minutes.count - 1)) }
        return runs
    }

    /// Mean minutes on `days` vs. every other day, and their ratio.
    static func compare(_ minutes: [Double], days: Set<Int>) -> (inside: Double?, outside: Double?, ratio: Double?) {
        let inside = mean(days.sorted().map { minutes[$0] })
        let outside = mean(minutes.indices.filter { !days.contains($0) }.map { minutes[$0] })
        guard let a = inside, let b = outside else { return (inside, outside, nil) }
        return (a, b, a / max(b, 0.5))
    }

    // MARK: Analysis

    public static func analyze(_ days: [DayRecord], calendar: Calendar = .current) -> InsightStats {
        let minutes = days.map(\.scratchMinutes)
        let n = minutes.count
        let base = baseline(minutes)
        let limit = threshold(baseline: base)
        let flares: [InsightStats.Flare] = flareRuns(minutes, threshold: limit).map { r in
            let slice = Array(minutes[r])
            let peak = slice.max() ?? 0
            let peakIndex = r.lowerBound + (slice.firstIndex(of: peak) ?? 0)
            return InsightStats.Flare(startIndex: r.lowerBound, endIndex: r.upperBound, start: days[r.lowerBound].day,
                                      end: days[r.upperBound].day, meanMinutes: mean(slice) ?? 0, peakMinutes: peak,
                                      peakDay: days[peakIndex].day)
        }
        let current = flares.last

        // Group exposures by kind + title.
        struct Group { var kind: ExposureKind; var title: String; var automatic: Bool; var indices: Set<Int> }
        var groups: [String: Group] = [:]
        var order: [String] = []
        for (i, d) in days.enumerated() {
            for e in d.exposures {
                let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = "\(e.kind.rawValue):\(title.lowercased())"
                if groups[id] == nil {
                    groups[id] = Group(kind: e.kind, title: title.isEmpty ? e.kind.label : title, automatic: e.automatic, indices: [])
                    order.append(id)
                }
                groups[id]?.indices.insert(i)
            }
        }

        var stats: [InsightStats.ExposureStat] = order.compactMap { id in
            guard let g = groups[id], let first = g.indices.min(), let last = g.indices.max() else { return nil }
            var after = Set<Int>()
            for i in g.indices { for lag in lagWindow where i + lag < n { after.insert(i + lag) } }
            let window = compare(minutes, days: after)

            var bestLag: Int?
            var bestRatio: Double?
            for lag in 0...lagWindow.upperBound {
                let shifted = Set(g.indices.map { $0 + lag }.filter { $0 < n })
                guard !shifted.isEmpty, shifted.count < n, let r = compare(minutes, days: shifted).ratio else { continue }
                if bestRatio == nil || r > bestRatio! + 1e-9 { bestRatio = r; bestLag = lag }
            }

            let onset: InsightStats.Onset
            var lead: Int?
            if let f = current {
                if first <= f.startIndex {
                    lead = f.startIndex - first
                    onset = lead! <= lagWindow.upperBound ? .beforeFlare : .longBefore
                } else {
                    onset = .afterFlareStart
                }
            } else {
                onset = .noFlare
            }

            let timing: Double = switch onset {
            case .beforeFlare: 1.25
            case .longBefore, .noFlare: 1
            case .afterFlareStart: 0.6
            }
            let evidence = g.indices.count >= 2 ? 1.0 : 0.8
            let score = (window.ratio ?? 1) * timing * evidence

            return InsightStats.ExposureStat(
                id: id, kind: g.kind, title: g.title, automatic: g.automatic, dayIndices: g.indices.sorted(),
                firstDay: days[first].day, lastDay: days[last].day, meanAfter: window.inside, meanOther: window.outside,
                effectRatio: window.ratio, bestLag: bestLag, bestLagRatio: bestRatio, onset: onset, leadDays: lead,
                presentOnLastDay: g.indices.contains(n - 1), score: score)
        }
        stats.sort { a, b in
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            return a.firstDay < b.firstDay
        }

        return InsightStats(windowStart: days.first?.day ?? Date(), windowEnd: days.last?.day ?? Date(), minutes: minutes,
                            baselineMinutes: base, thresholdMinutes: limit, flares: flares, exposures: stats,
                            cannotSeparate: confoundedGroups(stats))
    }

    /// Candidate exposures that started on the same or adjacent day and were present on nearly the same days.
    static func confoundedGroups(_ stats: [InsightStats.ExposureStat]) -> [[String]] {
        let candidates = stats.filter(\.isCandidate)
        var parent: [String: String] = [:]
        func root(_ x: String) -> String {
            var r = x
            while let p = parent[r], p != r { r = p }
            return r
        }
        for (i, a) in candidates.enumerated() {
            let firstA = a.dayIndices.first ?? 0
            for b in candidates[(i + 1)...] {
                let firstB = b.dayIndices.first ?? 0
                guard abs(firstA - firstB) <= 1 else { continue }
                let differ = Set(a.dayIndices).symmetricDifference(b.dayIndices).count
                guard differ < separatingDays else { continue }
                parent[a.id] = parent[a.id] ?? a.id
                parent[b.id] = parent[b.id] ?? b.id
                parent[root(b.id)] = root(a.id)
            }
        }
        var groups: [String: [String]] = [:]
        for s in candidates where parent[s.id] != nil { groups[root(s.id), default: []].append(s.id) }
        // Keep the engine's ranking inside each group and between groups.
        let rank = Dictionary(uniqueKeysWithValues: stats.enumerated().map { ($1.id, $0) })
        return groups.values
            .map { $0.sorted { rank[$0, default: 0] < rank[$1, default: 0] } }
            .sorted { rank[$0[0], default: 0] < rank[$1[0], default: 0] }
    }
}
