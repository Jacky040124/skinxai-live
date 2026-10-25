import Foundation

/// Douglas's longer history for the Trends tab: 60 nights before `StageStory`'s 14, so 74 nights that
/// end last night. The last 14 are `StageStory`'s nights exactly (same minutes, humidity, temperature,
/// sleep, exams, body wash, dry night). Claude's tools read the last 30 of them (`StageStory.runTool`).
///
/// Nights are numbered like `StageStory`'s: 0 = the oldest of the 14 … 13 = last night; the earlier
/// nights are −60 … −1 (night −60 started 74 days before today). `StageStory.nightDate(_:)` gives every
/// night's date, negative ones included.
///
/// What the earlier nights show (each Trends card reads one of these honestly):
/// - his usual is about 12 minutes a night, with ordinary night-to-night noise;
/// - an earlier flare two weeks before this one (nights −4 … −1, Oct 6–9 when today is Oct 24: 19, 27,
///   31 and 22 min). On the day before (night −5, Oct 5) he bought his first wool sweater and a
///   scented laundry detergent sample (both are in `StageStory.orders`); he wore the sweater and
///   washed with the sample on exactly those four nights and stopped both on the same day (night 0,
///   Oct 10). The data can't tell the two apart: same nights, same numbers. Only asking can;
/// - seven dry days (humidity under 35%, offshore wind) were calm, three of them in a heat wave;
/// - an exam week in mid-September didn't raise his scratching;
/// - late gym nights (sweat) are 2–3 minutes higher: a weak link;
/// - other new clothes (a hoodie, a T-shirt pack, then the wool socks) were washed before wearing: no rise;
/// - a short night of sleep doesn't make the next night worse;
/// - no weekday pattern;
/// - no body wash before night 10.
///
/// Every factor is compared on the nights outside the flares it can't explain: the body wash on the
/// nights without the sweater and the sample, those two on the nights without the body wash, the rest
/// on the nights outside both flares (`typicalNights`).
public enum StageHistory {

    // MARK: - Nights

    /// One night.
    public struct Night: Sendable, Hashable, Identifiable {
        /// The night's number (−60 … 13; 13 = last night).
        public let id: Int
        /// Minutes of scratching.
        public let minutes: Int
        public let episodes: Int
        /// Outdoor humidity that day, percent.
        public let humidity: Int
        /// High temperature that day, °F.
        public let highF: Int
        /// Hours asleep.
        public let sleepHours: Double
        public let wakeUps: Int
        /// He used the new body wash that day (night 10 on).
        public let bodyWash: Bool
        /// An exam week.
        public let exams: Bool
        /// A late workout (sweat) that evening.
        public let gym: Bool
        /// The first nights with newly bought clothes (washed before wearing).
        public let newClothes: Bool
        /// He wore the new wool sweater that evening (nights −4 … −1).
        public let woolSweater: Bool
        /// His clothes and sheets were washed with the scented detergent sample (nights −4 … −1).
        public let sampleDetergent: Bool

        /// Humidity under 35%.
        public var dry: Bool { humidity < StageStory.dryBelowPercent }
        /// Above 1.5 × usual.
        public var flare: Bool { Double(minutes) > StageStory.flareFactor * Double(StageStory.usual) }
    }

    /// Nights before `StageStory`'s 14: 60.
    public static let earlierCount = 60
    /// The oldest night's number: −60.
    public static var firstNight: Int { -earlierCount }
    /// Every night's number, oldest first: −60 … 13.
    public static var nightIDs: ClosedRange<Int> { firstNight...StageStory.lastNightIndex }
    /// 74.
    public static var count: Int { nightIDs.count }

    /// Every night, oldest first (74; the last 14 are `StageStory`'s).
    public static let nights: [Night] = nightIDs.map(makeNight)

    /// Night `i` (−60 … 13; clamped).
    public static func night(_ i: Int) -> Night {
        nights[min(max(i, firstNight), StageStory.lastNightIndex) - firstNight]
    }

    /// The nights before the new body wash (−60 … 9).
    public static var beforeBodyWash: [Night] { nights.filter { $0.id < StageStory.bodyWashNight } }

    /// The nights outside both flares: no body wash, no sweater, no sample (66). His usual.
    public static var typicalNights: [Night] { nights.filter { !$0.bodyWash && !$0.woolSweater && !$0.sampleDetergent } }

    /// The earlier flare: the nights with the wool sweater and the detergent sample (−4 … −1).
    public static let earlierFlareNights: ClosedRange<Int> = -4...(-1)
    /// The day he bought the wool sweater and the detergent sample: the day of night −5 (Oct 5). The
    /// `StageStory` orders are on that day.
    public static let earlierSuspectsBoughtNight = -5
    /// The two new things of the earlier flare, as the orders name them.
    public static let woolSweaterItem = "Northfield Lambswool Crewneck Sweater"
    public static let sampleDetergentItem = "FreshMeadow Spring Bloom Detergent, trial size"

    /// The night after a short one (under `shortSleepBelow` hours the night before).
    public static func afterShortSleep(_ i: Int) -> Bool {
        i > firstNight && night(i - 1).sleepHours < shortSleepBelow
    }
    /// Sleep under this many hours is a short night.
    public static let shortSleepBelow = 6.5

    /// Clothes he bought for the first time, and the night he first wore them (the socks are
    /// `StageStory`'s order on night 5, worn from night 6).
    public static let clothes: [(item: String, firstNight: Int)] = [
        ("Hoodie, cotton", -43),
        ("T-shirts, 3 pack", -19),
        ("Darn Tough Merino Wool Socks, 3 pairs", 6),
    ]

    // MARK: - Trigger impact

    /// A possible trigger.
    public enum Factor: String, CaseIterable, Sendable, Identifiable {
        case bodyWash, woolSweater, sampleDetergent, dryAir, exams, gym, shortSleep, newClothes
        public var id: String { rawValue }

        /// The flare the factor could explain (its own nights are never left out of its comparison).
        enum Flare { case bodyWash, earlier }
        var flare: Flare? {
            switch self {
            case .bodyWash: return .bodyWash
            case .woolSweater, .sampleDetergent: return .earlier
            default: return nil
            }
        }

        /// The nights this factor is compared on: every night, minus the flares it can't explain.
        public func inPool(_ night: Night) -> Bool {
            if night.bodyWash && flare != .bodyWash { return false }
            if (night.woolSweater || night.sampleDetergent) && flare != .earlier { return false }
            return true
        }

        /// Does it apply to night `night`?
        public func applies(to night: Night) -> Bool {
            switch self {
            case .bodyWash: return night.bodyWash
            case .woolSweater: return night.woolSweater
            case .sampleDetergent: return night.sampleDetergent
            case .dryAir: return night.dry
            case .exams: return night.exams
            case .gym: return night.gym
            case .shortSleep: return StageHistory.afterShortSleep(night.id)
            case .newClothes: return night.newClothes
            }
        }
    }

    /// How strong the association is. `possible`: a strong rise, but another factor was there on
    /// exactly the same nights, so the data can't tell which one it was.
    public enum Verdict: String, Sendable {
        case strong, possible, weak, none
    }

    /// Average minutes on nights with a factor against nights without it.
    public struct Impact: Sendable, Identifiable {
        public let factor: Factor
        public var id: String { factor.rawValue }
        public let withMinutes: Double
        public let withoutMinutes: Double
        public let withNights: Int
        public let withoutNights: Int
        /// Another factor on exactly the same nights (the sweater and the sample), if any.
        public let sameNightsAs: Factor?
        /// with − without, minutes.
        public var difference: Double { withMinutes - withoutMinutes }
        /// Rounded difference, e.g. +16.
        public var roundedDifference: Int { Int(difference.rounded()) }
        /// 5+ minutes more: strong (possible when another factor shares exactly its nights). 1.5–5:
        /// weak. Less (or lower): none.
        public var verdict: Verdict {
            if difference >= StageHistory.strongLinkMinutes { return sameNightsAs == nil ? .strong : .possible }
            if difference >= StageHistory.weakLinkMinutes { return .weak }
            return .none
        }
    }

    /// A difference at least this big (minutes) is a strong link.
    public static let strongLinkMinutes = 5.0
    /// At least this big (minutes) is a weak link.
    public static let weakLinkMinutes = 1.5

    /// The factor's impact over the 74 nights, compared on the nights outside the flares it can't
    /// explain (`Factor.inPool`), so one flare's nights don't make another factor look worse than it is
    /// (dry air "on its own").
    public static func impact(_ factor: Factor) -> Impact {
        let pool = nights.filter(factor.inPool)
        let with = pool.filter(factor.applies)
        let without = pool.filter { !factor.applies(to: $0) }
        let ids = Set(with.map(\.id))
        let twin = Factor.allCases.first { other in
            other != factor && !ids.isEmpty && Set(nights.filter(other.inPool).filter(other.applies).map(\.id)) == ids
        }
        return Impact(factor: factor, withMinutes: mean(with.map(\.minutes)), withoutMinutes: mean(without.map(\.minutes)),
                      withNights: with.count, withoutNights: without.count, sameNightsAs: twin)
    }

    /// Every factor's impact, in `Factor` order.
    public static var impacts: [Impact] { Factor.allCases.map(impact) }

    // MARK: - Weekdays

    /// Average minutes per weekday, Monday first, over the nights outside both flares (66 nights).
    /// Night dates are relative to `now`, but the groups are the same whatever the day.
    public static func weekdayAverages(now: Date = Date(), calendar: Calendar = .current) -> [Double] {
        let cal = StageStory.gregorian(calendar)
        var groups = Array(repeating: [Int](), count: 7)
        for n in typicalNights {
            let weekday = cal.component(.weekday, from: StageStory.nightDate(n.id, now: now, calendar: cal))   // 1 = Sunday
            groups[(weekday + 5) % 7].append(n.minutes)
        }
        return groups.map(mean)
    }

    /// Mean minutes a night outside both flares (≈ 12, his usual).
    public static var typicalAverage: Double { mean(typicalNights.map(\.minutes)) }

    // MARK: - Last night's sleep

    /// Last night's sleep stages (Apple Health style) from 11:04 PM to 6:52 AM, made to agree with
    /// `StageStory`: 5.1 h asleep, woke up twice, each time right after a scratching bout in
    /// `StageStory.LastNight.quarterHours`.
    public enum LastNightSleep {
        public enum Stage: String, CaseIterable, Sendable {
            case awake, rem, core, deep
        }

        /// A stretch of one stage, in minutes after 11:04 PM.
        public struct Segment: Sendable, Hashable {
            public let stage: Stage
            public let start: Int
            public let end: Int
            public var minutes: Int { end - start }
        }

        /// 11:04 PM … 6:52 AM: 468 minutes.
        public static let length = 468
        /// 11:04 PM is 4 minutes after the first quarter hour (11:00 PM).
        public static let offsetIntoFirstQuarter = 4

        /// The stages, in order, covering 0 … 468 without gaps.
        public static let segments: [Segment] = {
            let plan: [(Stage, Int)] = [
                (.core, 14), (.deep, 52), (.core, 70), (.rem, 82), (.core, 104), (.deep, 130), (.core, 150),
                (.rem, 170), (.core, 211),
                (.awake, 301),                                   // 2:35–4:05 AM, after the 2:30 bout
                (.core, 320), (.deep, 332), (.core, 346),
                (.awake, 418),                                   // 4:50–6:02 AM, after the 4:45 bout
                (.core, 440), (.rem, 468),
            ]
            var start = 0
            return plan.map { stage, end in
                defer { start = end }
                return Segment(stage: stage, start: start, end: end)
            }
        }()

        /// Minutes asleep (every stage but awake): 306 = 5.1 h.
        public static var minutesAsleep: Int { segments.filter { $0.stage != .awake }.map(\.minutes).reduce(0, +) }

        /// The wake-ups: the awake stretches (2).
        public static var wakeUps: [Segment] { segments.filter { $0.stage == .awake } }

        /// The quarter hour (0 … 31 from 11:00 PM) that minute `t` after 11:04 PM falls in.
        public static func quarter(at t: Int) -> Int {
            min(max((t + offsetIntoFirstQuarter) / 15, 0), StageStory.LastNight.quarterHours.count - 1)
        }

        /// He scratched (at least a minute) in the quarter hour just before waking up.
        public static func followsScratching(_ wake: Segment) -> Bool {
            StageStory.LastNight.quarterHours[quarter(at: wake.start - 5)] >= 1
        }

        /// Wake-ups that came right after a scratching bout (2 of 2).
        public static var wakeUpsAfterScratching: Int { wakeUps.filter(followsScratching).count }
    }

    // MARK: - Data

    // Nights −60 … −1 (Tue Aug 11 … Fri Oct 9 when today is Sat Oct 24). The last four are the earlier
    // flare (Oct 6–9).
    static let earlierMinutes: [Int] = [14, 12, 15, 10, 14, 14, 12, 15, 12, 10, 9, 14, 12, 10, 12, 10, 13, 12, 14, 11,
                                        14, 13, 12, 13, 14, 11, 13, 10, 14, 10, 13, 11, 11, 10, 14, 13, 14, 9, 12, 15,
                                        12, 11, 12, 13, 10, 9, 12, 10, 16, 12, 10, 13, 11, 11, 14, 10, 19, 27, 31, 22]
    static let earlierEpisodes: [Int] = [12, 9, 11, 9, 11, 12, 10, 12, 10, 8, 7, 11, 11, 7, 10, 8, 9, 9, 11, 10,
                                         11, 10, 10, 10, 11, 10, 10, 7, 11, 9, 9, 10, 9, 8, 12, 10, 10, 7, 11, 12,
                                         11, 10, 10, 10, 8, 8, 11, 8, 12, 10, 9, 10, 10, 9, 11, 7, 14, 18, 20, 15]
    static let earlierHumidity: [Int] = [63, 68, 55, 62, 52, 68, 48, 68, 30, 66, 44, 46, 46, 31, 52, 71, 56, 66, 68, 60,
                                         47, 45, 31, 30, 53, 59, 45, 58, 64, 48, 47, 32, 59, 53, 47, 71, 60, 69, 55, 52,
                                         64, 61, 53, 52, 28, 60, 53, 49, 63, 50, 68, 29, 49, 58, 51, 71, 61, 61, 70, 48]
    static let earlierHighF: [Int] = [71, 70, 74, 70, 69, 68, 69, 70, 77, 70, 72, 72, 71, 81, 67, 73, 76, 69, 70, 72,
                                      76, 71, 90, 91, 87, 67, 68, 75, 65, 76, 67, 76, 76, 72, 71, 70, 77, 77, 73, 77,
                                      67, 77, 78, 75, 81, 67, 76, 74, 73, 67, 75, 74, 69, 67, 67, 68, 71, 70, 64, 64]
    static let earlierSleep: [Double] = [7.6, 7.5, 7.7, 6.7, 7.8, 5.5, 6.7, 7.9, 7.3, 7.9, 7.2, 7.1, 7.1, 7.3, 6.3, 6.7, 7.7, 7.4, 7.8, 7.8,
                                         7.6, 7.8, 7.4, 7.4, 7.7, 7.6, 7.6, 5.8, 7.7, 7.4, 7.2, 7.2, 7.6, 5.8, 7.7, 6.9, 7.4, 7.6, 7.5, 7.9,
                                         7.4, 7.0, 7.3, 7.1, 7.9, 6.9, 5.5, 7.6, 7.6, 7.4, 6.9, 7.8, 6.9, 7.2, 6.7, 7.7, 6.8, 6.6, 6.6, 6.9]
    static let earlierWakeUps: [Int] = [0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0,
                                        0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0,
                                        0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 2, 2, 1]
    /// An exam week in mid-September (Mon–Thu), and the midterms.
    static let examNights: Set<Int> = Set(-26...(-23)).union(StageStory.examNights)
    /// Late workouts, spread over the weekdays.
    static let gymNights: Set<Int> = [-58, -53, -49, -44, -40, -34, -30, -21, -17, -12, -6, -2, 4, 7]
    /// The first three nights in each new piece of clothing.
    static var clothesNights: Set<Int> {
        Set(clothes.flatMap { $0.firstNight...($0.firstNight + 2) })
    }

    private static func makeNight(_ i: Int) -> Night {
        let clothes = clothesNights
        let earlier = earlierFlareNights.contains(i)
        if i >= 0 {
            return Night(id: i, minutes: StageStory.nights[i], episodes: StageStory.episodes[i],
                         humidity: StageStory.humidity[i], highF: StageStory.highF[i],
                         sleepHours: StageStory.sleepHours[i], wakeUps: StageStory.wakeUps[i],
                         bodyWash: i >= StageStory.bodyWashNight, exams: examNights.contains(i),
                         gym: gymNights.contains(i), newClothes: clothes.contains(i),
                     woolSweater: earlier, sampleDetergent: earlier)
        }
        let k = i + earlierCount
        return Night(id: i, minutes: earlierMinutes[k], episodes: earlierEpisodes[k],
                     humidity: earlierHumidity[k], highF: earlierHighF[k],
                     sleepHours: earlierSleep[k], wakeUps: earlierWakeUps[k],
                     bodyWash: false, exams: examNights.contains(i),
                     gym: gymNights.contains(i), newClothes: clothes.contains(i),
                     woolSweater: earlier, sampleDetergent: earlier)
    }

    private static func mean(_ values: [Int]) -> Double {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }
}
