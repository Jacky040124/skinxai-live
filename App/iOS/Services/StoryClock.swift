import Foundation
import EczemaKit

/// A point on the demo timeline: a day of the 14-day flare story, or a day of the 10-day test.
enum StoryPoint: Hashable {
    case flare(Int)   // 1...14 (14 = the default story: today, case file ready)
    case test(Int)    // 1...10

    static let flareLength = DemoData.flareMinutes.count
    static let testLength = DemoData.experimentMinutes.count

    /// All stops, oldest first (used by the time-travel scrubber).
    static var all: [StoryPoint] {
        (1...flareLength).map { .flare($0) } + (1...testLength).map { .test($0) }
    }

    /// Scratch minutes of that day in the story (for the scrubber's mini bars).
    var minutes: Double {
        switch self {
        case .flare(let d): DemoData.flareMinutes[d - 1]
        case .test(let d): DemoData.experimentMinutes[d - 1]
        }
    }

    var index: Int {
        switch self {
        case .flare(let d): d - 1
        case .test(let d): StoryPoint.flareLength + d - 1
        }
    }
}

/// Demo time travel inside the flare story (days 1–13). Day 14 and the test days come straight
/// from `DemoData.make`. Earlier days keep the window 14 days long (calm days in front) so every
/// screen sees the same shape of data; Claude's case file only exists from day 14.
enum StoryClock {
    /// The demo dataset for a point of the timeline, with today revealed through
    /// `DemoData.storyRevealHour` (so last night's scratching is always there).
    /// `reveal` overrides the hour today is revealed through (QA only).
    static func dataset(at point: StoryPoint, now: Date = Date(), reveal: Int? = nil,
                        calendar: Calendar = .current) -> TwinDataset {
        switch point {
        case .flare(let d): flareStory(day: d, now: now, reveal: reveal, calendar: calendar)
        case .test(let d):
            DemoData.make(today: now, experimentDay: min(max(d, 1), StoryPoint.testLength),
                          revealThroughHour: reveal ?? DemoData.storyRevealHour(at: now, calendar: calendar), calendar: calendar)
        }
    }

    static func flareStory(day: Int, now: Date = Date(), reveal: Int? = nil, calendar: Calendar = .current) -> TwinDataset {
        let n = StoryPoint.flareLength
        let day = min(max(day, 1), n)
        let reveal = reveal ?? DemoData.storyRevealHour(at: now, calendar: calendar)
        if day == n { return DemoData.make(today: now, revealThroughHour: reveal, calendar: calendar) }

        // Generate the story so that story day `day` lands on today's date.
        let shift = n - day
        let shifted = calendar.date(byAdding: .day, value: shift, to: now) ?? now
        let full = DemoData.make(today: shifted, calendar: calendar)
        var story = Array(full.days.prefix(day))
        guard let first = story.first else { return DemoData.make(today: now, revealThroughHour: reveal, calendar: calendar) }

        // Calm days in front, so the window stays 14 days long.
        let calm = Array(full.days.prefix(DemoData.flareStartDay))
        var pad: [DayRecord] = []
        for k in 0..<shift {
            guard let date = calendar.date(byAdding: .day, value: -(shift - k), to: first.day) else { continue }
            var record = calm[k % calm.count]
            record.day = date
            record.exposures = record.exposures
                .filter { $0.kind == .sweat || $0.kind == .dairy }
                .map { Exposure(kind: $0.kind, title: $0.title, day: date, automatic: $0.automatic) }
            pad.append(record)
        }

        // Today: hours after "now" haven't happened yet (but last night always has).
        var today = story[story.count - 1]
        for h in 0..<24 where h > reveal { today.scratchMinutesByHour[h] = 0 }
        story[story.count - 1] = today

        var days = pad + story
        var rng = SplitMix64(seed: 0x57A2_C10C &+ UInt64(day))
        var episodes: [ScratchEpisode] = []
        for i in max(0, days.count - 3)..<days.count {
            let made = makeEpisodes(for: days[i], rng: &rng)
            days[i].episodeCount = made.count
            days[i].intenseCount = made.filter(\.intense).count
            episodes += made
        }
        return TwinDataset(days: days, episodes: episodes, baselineMinutesPerDay: full.baselineMinutesPerDay,
                           caseFile: nil, experiment: nil, isDemo: true)
    }

    /// Splits a day's hourly minutes into scratch episodes (same shape as the demo generator).
    private static func makeEpisodes(for record: DayRecord, rng: inout SplitMix64) -> [ScratchEpisode] {
        let flare = record.scratchMinutes > 20
        var out: [ScratchEpisode] = []
        for h in 0..<24 where record.scratchMinutesByHour[h] > 0.05 {
            var left = record.scratchMinutesByHour[h] * 60
            var t = record.day.addingTimeInterval(Double(h) * 3600 + rng.next() * 300)
            while left > 5 {
                let len = min(left, 20 + rng.next() * 100)
                let intense = rng.next() < (flare ? 0.18 : 0.05)
                let rms = intense ? 0.36 + rng.next() * 0.3 : 0.12 + rng.next() * 0.2
                out.append(ScratchEpisode(start: t, end: t.addingTimeInterval(len), meanHz: 2.8 + rng.next() * 2.8,
                                          meanRMS: rms, intense: intense, source: .demo))
                left -= len
                t = t.addingTimeInterval(len + 30 + rng.next() * (3600 / max(1, record.scratchMinutesByHour[h])))
            }
        }
        return out
    }
}
