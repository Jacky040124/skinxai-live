import Foundation
import EczemaKit

/// The demo story at the day the iPhone shows, built the same way the iPhone builds it, so both
/// show the same minutes, episodes and usual: the flare story (`DemoData.make`), a day of the
/// 10-day test (`experimentDay`), or an earlier day of the flare story (the iPhone's demo time
/// travel, `StoryClock.flareStory` in App/iOS/Services — mirrored below, keep the two in step).
enum WatchDemoStory {
    static func dataset(for context: PhoneContext, now: Date = Date(), calendar: Calendar = .current) -> TwinDataset {
        // Built at the moment the iPhone built its story (same day only), so "today so far" ends at
        // the same hour on both.
        let at = context.storyAt.flatMap { calendar.isDate($0, inSameDayAs: now) && $0 <= now ? $0 : nil } ?? now
        // Today is revealed through the same hour as on the iPhone (`DemoData.storyRevealHour`:
        // never before 7 am, so a night rehearsal shows last night's flare on both).
        let reveal = DemoData.storyRevealHour(at: at, calendar: calendar)
        if let day = context.expDay {
            return DemoData.make(today: at, experimentDay: day, revealThroughHour: reveal, calendar: calendar)
        }
        if let day = context.storyDay { return flareStory(day: day, now: at, calendar: calendar) }
        return DemoData.make(today: at, revealThroughHour: reveal, calendar: calendar)
    }

    /// Day `day` (1...14) of the flare story as today. Mirrors `StoryClock.flareStory(day:)`.
    static func flareStory(day: Int, now: Date, calendar: Calendar) -> TwinDataset {
        let n = DemoData.flareMinutes.count
        let day = min(max(day, 1), n)
        let reveal = DemoData.storyRevealHour(at: now, calendar: calendar)
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

    /// Splits a day's hourly minutes into scratch episodes (same shape and seed as the iPhone).
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
