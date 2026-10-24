import SwiftUI
import EczemaKit

/// What the Today tab shows, all from `StageStory`: the same numbers Claude's tools read.
/// Text is English and dates are Gregorian in the phone's time zone, like `StageStory`'s helpers.
enum TodayStory {
    typealias Last = StageStory.LastNight

    /// The Gregorian calendar in the phone's time zone (`StageStory` dates are Gregorian everywhere).
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// "SAT · OCT 24" (the top bar).
    static func topBarDate(_ now: Date = Date()) -> String {
        "\(StageStory.weekday(now, short: true, calendar: calendar)) · \(StageStory.monthDay(now, calendar: calendar))".uppercased()
    }

    /// "11:04 PM – 6:52 AM"
    static var sleepWindow: String { "\(Last.asleep) – \(Last.awake)" }

    /// The ring is full at 3.6 × your usual: last night's 41 min fill it almost all the way.
    static var ringProgress: Double { Double(Last.minutes) / (Double(StageStory.usual) * 3.6) }

    /// Last night ÷ your usual (41 / 12 ≈ 3.4).
    static var ratio: Double { StageStory.ratio(StageStory.lastNightIndex) }

    /// A quarter hour with more than this many minutes is part of the bad stretch (orange).
    static let hotQuarterHour = 2.2

    /// "11p 1a 3a 5a 7a": every two hours from bedtime to the end of the last hour.
    static var quarterHourLabels: [QuarterHourChart.AxisLabel] {
        let hours = Last.minutesPerHour.count
        return stride(from: 0, through: hours, by: 2).map { k in
            let h = (Last.firstHour + k) % 24
            let h12 = h % 12 == 0 ? 12 : h % 12
            return QuarterHourChart.AxisLabel(text: "\(h12)\(h < 12 ? "a" : "p")", at: Double(k) / Double(hours))
        }
    }

    /// "Up 3 nights in a row" (the pink card; it never says why).
    static var ctaTitle: String {
        let streak = StageStory.flareStreak
        return streak >= 2 ? "Up \(streak) nights in a row" : "Last night was above your usual"
    }

    /// The last `n` nights of a value, last night last (the mini cards' spark bars).
    static func recent(_ values: [Double], _ n: Int = 7) -> [Double] { Array(values.suffix(n)) }

    /// Your usual sleep: the median of the nights before the new body wash.
    static var usualSleep: Double {
        let before = StageStory.sleepHours.prefix(StageStory.bodyWashNight).sorted()
        guard !before.isEmpty else { return Last.sleepHours }
        let m = before.count / 2
        return before.count % 2 == 0 ? (before[m - 1] + before[m]) / 2 : before[m]
    }
}

// MARK: - Launch arguments (debug builds: screenshots and recordings)

enum TodayTrendsLaunch {
    /// `-scrollTo bottom`: scroll the tab to its end after the entrance. (Anchoring the end marker at
    /// the top makes the scroll view stop at its last offset, with the content clear of the tab bar.)
    static func scrollForScreenshot(_ proxy: ScrollViewProxy, bottomID: String) {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "scrollTo") == "bottom" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(Twin.Motion.slide) { proxy.scrollTo(bottomID, anchor: .top) }
        }
        #endif
    }

    /// `-trendsRange week|twoWeeks|all`: the Trends range at launch.
    static var trendsRange: TrendsRange? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsRange").flatMap(TrendsRange.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// `-trendsSelect 5`: Trends selects that night (0 = oldest … 13 = last night) after its entrance,
    /// as if it had been tapped.
    static var trendsSelect: Int? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsSelect").flatMap(Int.init)
        #else
        return nil
        #endif
    }

    /// `-trendsTour 1`: a scripted walk through the Trends chart (screen recordings).
    static var trendsTour: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "trendsTour")
        #else
        return false
        #endif
    }
}

extension View {
    /// Calls `action` when the calendar day changes (midnight, a time zone or clock change) or the app
    /// comes back to the front, so "last night" and the dates follow the clock while the app stays open.
    func onNewDay(_ action: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in action() }
    }
}
