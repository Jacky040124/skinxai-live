import Foundation
import Testing
@testable import EczemaKit

@Suite struct StageHistoryTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// Saturday, October 24, 2026, 3 PM in Berkeley (the first demo day).
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))! }

    @Test func shape() {
        #expect(StageHistory.count == 74 && StageHistory.nights.count == 74)
        #expect(StageHistory.nights.first?.id == -60 && StageHistory.nights.last?.id == 13)
        #expect(StageHistory.nights.map(\.id) == Array(-60...13))
        for array in [StageHistory.earlierMinutes.count, StageHistory.earlierEpisodes.count, StageHistory.earlierHumidity.count,
                      StageHistory.earlierHighF.count, StageHistory.earlierSleep.count, StageHistory.earlierWakeUps.count] {
            #expect(array == 60)
        }
        // Dates: the oldest night is Tue Aug 11, last night Fri Oct 23.
        #expect(StageStory.iso(StageStory.nightDate(-60, now: now, calendar: cal), calendar: cal) == "2026-08-11")
        #expect(StageStory.iso(StageStory.nightDate(13, now: now, calendar: cal), calendar: cal) == "2026-10-23")
    }

    @Test func lastFourteenAreTheStory() {
        let last = Array(StageHistory.nights.suffix(14))
        #expect(last.map(\.id) == Array(0...13))
        #expect(last.map(\.minutes) == StageStory.nights)
        #expect(last.map(\.episodes) == StageStory.episodes)
        #expect(last.map(\.humidity) == StageStory.humidity)
        #expect(last.map(\.highF) == StageStory.highF)
        #expect(last.map(\.sleepHours) == StageStory.sleepHours)
        #expect(last.map(\.wakeUps) == StageStory.wakeUps)
        #expect(last.filter(\.exams).map(\.id) == Array(StageStory.examNights))
        #expect(last.filter(\.bodyWash).map(\.id) == Array(StageStory.bodyWashNight...13))
        #expect(last.filter(\.dry).map(\.id) == [StageStory.dryAirNight])
        // The story itself is untouched.
        #expect(StageStory.nights == [9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41])
    }

    @Test func earlierNightsTellHonestStories() {
        let earlier = StageHistory.nights.prefix(60)
        #expect(!earlier.contains { $0.bodyWash })
        // The only earlier flare: the sweater-and-sample nights, Oct 6–9.
        #expect(earlier.filter(\.flare).map(\.id) == Array(StageHistory.earlierFlareNights))
        #expect(earlier.filter(\.flare).map(\.minutes) == [19, 27, 31, 22])
        // Usual ~12 with noise.
        let typical = StageHistory.typicalNights
        #expect(typical.count == 66)
        #expect(abs(StageHistory.typicalAverage - 12) < 0.5)
        #expect(typical.map(\.minutes).min()! >= 8 && typical.map(\.minutes).max()! <= 16)
        // Several calm dry days.
        let dry = earlier.filter(\.dry)
        #expect(dry.count >= 5)
        #expect(dry.allSatisfy { $0.minutes <= 13 })
        // An earlier exam week, a few new clothes.
        #expect(earlier.filter(\.exams).count == 4)
        #expect(StageHistory.clothes.count == 3 && earlier.filter(\.newClothes).count == 6)
        // The socks are StageStory's order on night 5, worn from night 6.
        #expect(StageHistory.clothes.last?.firstNight == 6)
        #expect(StageStory.orders(now: now, calendar: cal).contains { $0.item.hasPrefix("Darn Tough Merino Wool Socks") })
    }

    @Test func theEarlierFlare() {
        // Bought Oct 5, both used on exactly Oct 6–9, both stopped Oct 10.
        let iso = { (i: Int) in StageStory.iso(StageStory.nightDate(i, now: now, calendar: cal), calendar: cal) }
        #expect(iso(StageHistory.earlierSuspectsBoughtNight) == "2026-10-05")
        #expect(StageHistory.earlierFlareNights.map(iso) == ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"])
        #expect(StageHistory.nights.filter(\.woolSweater).map(\.id) == Array(StageHistory.earlierFlareNights))
        #expect(StageHistory.nights.filter(\.sampleDetergent).map(\.id) == Array(StageHistory.earlierFlareNights))
        #expect(!StageHistory.night(0).woolSweater && !StageHistory.night(0).sampleDetergent)
        // Normal weather on those nights.
        #expect(StageHistory.earlierFlareNights.map(StageHistory.night).allSatisfy { !$0.dry && $0.highF < 85 })
    }

    @Test func verdicts() {
        let v = Dictionary(uniqueKeysWithValues: StageHistory.impacts.map { ($0.factor, $0) })
        #expect(v[.bodyWash]!.verdict == .strong)
        #expect(v[.bodyWash]!.withNights == 4 && v[.bodyWash]!.withoutNights == 66)
        #expect(v[.bodyWash]!.roundedDifference == 16)
        #expect(v[.bodyWash]!.sameNightsAs == nil)
        // The sweater and the sample: the same nights, the same numbers; the data can't separate them.
        let sweater = v[.woolSweater]!, sample = v[.sampleDetergent]!
        #expect(sweater.verdict == .possible && sample.verdict == .possible)
        #expect(sweater.sameNightsAs == .sampleDetergent && sample.sameNightsAs == .woolSweater)
        #expect(sweater.withMinutes == sample.withMinutes && sweater.withoutMinutes == sample.withoutMinutes)
        #expect(sweater.withNights == 4 && sweater.withoutNights == 66)
        #expect(sweater.roundedDifference == 13)
        #expect(v[.gym]!.verdict == .weak)
        #expect((2...4).contains(v[.gym]!.roundedDifference))
        for f in [StageHistory.Factor.dryAir, .exams, .shortSleep, .newClothes] {
            #expect(v[f]!.verdict == .none, "\(f)")
            #expect(abs(v[f]!.difference) < 1, "\(f)")
        }
        // Dry air "on its own": the dry nights outside both flares.
        #expect(v[.dryAir]!.withNights == 7 && v[.dryAir]!.withoutNights == 59)
        #expect(v[.exams]!.withNights == 7)
        #expect(v[.newClothes]!.withNights == 9)
    }

    @Test func noWeekdayPattern() {
        // The same groups on either demo day.
        for day in [24, 25] {
            let at = cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 15))!
            let averages = StageHistory.weekdayAverages(now: at, calendar: cal)
            #expect(averages.count == 7)
            #expect(averages.allSatisfy { abs($0 - Double(StageStory.usual)) <= 2 })
        }
    }

    @Test func weatherIsNotLinked() {
        // Outside the flares, humidity and temperature don't move the minutes.
        let before = StageHistory.typicalNights
        #expect(abs(correlation(before.map { Double($0.humidity) }, before.map { Double($0.minutes) })) < 0.2)
        #expect(abs(correlation(before.map { Double($0.highF) }, before.map { Double($0.minutes) })) < 0.2)
        // Every night above 1.5× usual is a body-wash night or a sweater-and-sample night.
        #expect(StageHistory.nights.filter { $0.flare }.allSatisfy { $0.bodyWash || $0.woolSweater })
    }

    @Test func lastNightSleep() {
        typealias S = StageHistory.LastNightSleep
        #expect(S.segments.first?.start == 0 && S.segments.last?.end == S.length)
        for (a, b) in zip(S.segments, S.segments.dropFirst()) {
            #expect(a.end == b.start && a.stage != b.stage)
        }
        #expect(S.segments.allSatisfy { $0.minutes > 0 })
        #expect(S.minutesAsleep == Int((StageStory.LastNight.sleepHours * 60).rounded()))
        #expect(S.wakeUps.count == StageStory.LastNight.wakeUps)
        #expect(S.wakeUps.count == 2 && S.wakeUpsAfterScratching == 2)
        #expect(S.length == 7 * 60 + 48)   // 11:04 PM → 6:52 AM
    }

    private func correlation(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        let cov = zip(x, y).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let vx = x.map { ($0 - mx) * ($0 - mx) }.reduce(0, +), vy = y.map { ($0 - my) * ($0 - my) }.reduce(0, +)
        return cov / (vx * vy).squareRoot()
    }
}
