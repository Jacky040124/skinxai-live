#if DEBUG
import Foundation
import EczemaKit

/// QA fixtures for the Today and Trends tabs in real-data mode (debug builds only).
/// `-ttFixture <name>` replaces the dataset once at launch with a "real" dataset built by the
/// same pipeline real mode uses (`RealDataBuilder`), from synthetic watch episodes, Apple Health
/// entries and a weather report. Lets screenshots show what a simulator cannot produce.
///   realPartial  watch from 7 days ago, Health with gaps (sleep and HRV missing on some
///                days), dry-air days, weather loaded but no AQI today
///   realNew      two tracked nights (usual = starting estimate), no Health, weather loaded
@MainActor
enum TodayTrendsFixture {
    private static var applied = false

    static func applyIfRequested(_ app: AppState) {
        guard !applied, let name = UserDefaults.standard.string(forKey: "ttFixture") else { return }
        applied = true
        guard let dataset = make(name) else { return }
        app.update { $0 = dataset }
    }

    static func make(_ name: String, now: Date = Date(), calendar: Calendar = .current) -> TwinDataset? {
        let today = calendar.startOfDay(for: now)
        func day(_ i: Int) -> Date { calendar.date(byAdding: .day, value: i - 13, to: today) ?? today }

        // Minutes per tracked day (index 13 = today), sleep and HRV per day (nil = Health had nothing).
        let minutes: [Int: Double]
        let sleep: [Int: Double]
        let hrv: [Int: Double]
        let humidity: [Double]
        switch name {
        case "realPartial":
            minutes = [7: 9, 8: 14, 9: 23, 10: 31, 11: 26, 12: 12, 13: 4]
            sleep = [2: 7.4, 3: 7.1, 4: 6.9, 5: 7.6, 6: 7.2, 9: 5.6, 10: 5.1, 11: 6.0, 12: 6.8, 13: 7.0]
            hrv = [4: 51, 5: 48, 6: 50, 10: 37, 11: 41, 12: 45, 13: 47]
            humidity = [58, 61, 55, 52, 49, 44, 33, 29, 31, 30, 38, 46, 52, 41]
        case "realNew":
            minutes = [11: 8, 12: 15, 13: 3]
            sleep = [:]
            hrv = [:]
            humidity = [62, 60, 58, 57, 61, 64, 59, 55, 52, 50, 54, 57, 60, 58]
        default:
            return nil
        }

        // Watch episodes: 90-second runs between 1 and 4 am (today too, so they are in the past).
        var episodes: [ScratchEpisode] = []
        for (i, total) in minutes.sorted(by: { $0.key < $1.key }) {
            let count = max(1, Int((total * 60 / 90).rounded()))
            let start = day(i).addingTimeInterval(3600)
            let gap = 3 * 3600 / Double(count)
            for k in 0..<count {
                let t = start.addingTimeInterval(Double(k) * gap)
                episodes.append(ScratchEpisode(start: t, end: t.addingTimeInterval(90), meanHz: 3.2 + Double(k % 5) * 0.4,
                                               meanRMS: k % 6 == 0 ? 0.41 : 0.22, intense: k % 6 == 0, source: .recorded))
            }
        }

        var saved = RealSaved()
        saved.health = (0..<14).map { i in
            RealSaved.HealthEntry(day: day(i), sleepHours: sleep[i], wakeUps: sleep[i].map { $0 < 6.5 ? 4 : 1 },
                                  hrvMs: hrv[i], restingHR: hrv[i].map { _ in 60 }, workoutMinutes: i == 9 ? 40 : 0)
        }
        let daily = (0..<14).map { i in
            EnvironmentReading(time: day(i), humidityPct: humidity[i], tempC: 9 + Double(i % 4),
                               aqi: 30 + (i * 7) % 25, pollen: .unknown)
        }
        // Weather loaded this morning; the air-quality feed failed (no AQI now).
        saved.environment = EnvironmentReport(latitude: 37.87, longitude: -122.27, fetchedAt: now,
                                              current: EnvironmentReading(time: now, humidityPct: humidity[13], tempC: 11.4,
                                                                          aqi: nil, pollen: .unknown),
                                              daily: daily)
        return RealDataBuilder.build(now: now, calendar: calendar, episodes: episodes, saved: saved)
    }
}
#endif
