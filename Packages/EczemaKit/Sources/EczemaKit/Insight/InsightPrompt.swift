import Foundation

/// Builds what the model reads: the bundled system prompt and a user message with the stats table + daily log.
public enum InsightPrompt {
    public static let resourceName = "InsightSystemPrompt"

    /// The system prompt bundled with the package (`Resources/InsightSystemPrompt.txt`).
    public static func systemPrompt() -> String? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// The user message: today's context, the app's stats and the daily log (oldest first).
    public static func userMessage(dataset: TwinDataset, stats: InsightStats, now: Date = Date(),
                                   calendar: Calendar = .current) -> String {
        let f = Formats(calendar: calendar)
        var out: [String] = []
        out.append("Today is \(f.weekdayDay(now)), \(f.time(now)). Today's row is partial (the day is not over).")
        out.append("Window: \(f.day(stats.windowStart)) – \(f.day(stats.windowEnd)) (\(stats.dayCount) days). "
                   + "\"Scratch min\" = minutes of scratching measured by the watch.")
        if let e = dataset.experiment {
            let day = dataset.experimentDays(calendar: calendar).count
            out.append("Running test: \"\(e.plan.title)\" since \(f.day(e.startDay)) (day \(max(day, 1)) of \(e.plan.lengthDays)), "
                       + "status \(e.status.rawValue). Before the test: \(f.num(e.baselineMinutesPerDay)) min/day.")
        }

        out.append("")
        out.append("## Stats computed by the app (trust these numbers)")
        out.append("- Usual scratching (median of calm days): \(f.num(stats.baselineMinutes)) min/day")
        out.append("- Flare threshold (1.5 × usual): \(f.num(stats.thresholdMinutes)) min/day")
        if stats.flares.isEmpty {
            out.append("- Flares (2+ days in a row above the threshold): none")
        } else {
            for fl in stats.flares {
                out.append("- Flare: \(f.day(fl.start)) – \(f.day(fl.end)), \(fl.days) days, mean \(f.num(fl.meanMinutes)) min/day, "
                           + "peak \(f.num(fl.peakMinutes)) min on \(f.day(fl.peakDay))")
            }
        }
        if stats.exposures.isEmpty {
            out.append("- Exposures: none logged")
        } else {
            out.append("- Exposures in the order they started (mean scratch min on the 1–3 days after it vs. all other days):")
            for e in stats.exposures.sorted(by: { ($0.firstDay, $0.title) < ($1.firstDay, $1.title) }) {
                var parts: [String] = []
                parts.append("\(e.daysPresent) day\(e.daysPresent == 1 ? "" : "s") (\(f.range(e.firstDay, e.lastDay)))")
                parts.append(onsetText(e, f: f))
                if let a = e.meanAfter, let o = e.meanOther, let r = e.effectRatio {
                    parts.append("after \(f.num(a)) vs other \(f.num(o)) → \(f.ratio(r))")
                } else {
                    parts.append("effect: not enough days to compare")
                }
                if let lag = e.bestLag, let r = e.bestLagRatio {
                    parts.append("strongest at lag \(lag) day\(lag == 1 ? "" : "s") (\(f.ratio(r)))")
                }
                let source = e.automatic ? "automatic" : "tagged by them"
                out.append("  - \(e.title) [kind \(e.kind.rawValue), \(source)]: " + parts.joined(separator: "; "))
            }
        }
        if stats.cannotSeparate.isEmpty {
            out.append("- Cannot separate: none")
        } else {
            for group in stats.cannotSeparate {
                let names = group.compactMap { stats.exposure(id: $0)?.title }
                out.append("- Cannot separate yet: \(names.joined(separator: " + ")) (started within a day of each other "
                           + "and were present together almost every day)")
            }
        }

        out.append("")
        out.append("## Daily log (oldest first)")
        out.append("date | scratch min | worst hour | episodes (intense) | sleep h | wake-ups | HRV ms | resting HR | humidity % | temp °C | AQI | pollen | exposures")
        let lastIndex = dataset.days.count - 1
        for (i, d) in dataset.days.enumerated() {
            let date = f.day(d.day) + (i == lastIndex ? " (today, partial)" : "")
            let worst = d.worstHour.map { f.hour($0) } ?? "—"
            let exposures = d.exposures.isEmpty ? "—" : d.exposures.map { e in
                e.note.map { "\(e.title) (\($0))" } ?? e.title
            }.joined(separator: ", ")
            out.append([date, f.num(d.scratchMinutes), worst, "\(d.episodeCount) (\(d.intenseCount))", f.num(d.sleepHours),
                        "\(d.wakeUps)", f.num(d.hrvMs), f.num(d.restingHR), f.num(d.humidityPct), f.num(d.tempC),
                        "\(d.aqi)", d.pollen.rawValue, exposures].joined(separator: " | "))
        }
        out.append("")
        out.append("Find this person's likely flare triggers. Reply with JSON only.")
        return out.joined(separator: "\n")
    }

    static func onsetText(_ e: InsightStats.ExposureStat, f: Formats) -> String {
        switch e.onset {
        case .beforeFlare, .longBefore:
            let lead = e.leadDays ?? 0
            return lead == 0 ? "started the day the flare began" : "started \(lead) day\(lead == 1 ? "" : "s") before the flare began"
        case .afterFlareStart: return "started after the flare had begun"
        case .noFlare: return "no flare to compare with"
        }
    }

    struct Formats {
        let calendar: Calendar
        private let dayF: DateFormatter
        private let weekdayF: DateFormatter
        private let timeF: DateFormatter

        init(calendar: Calendar) {
            self.calendar = calendar
            func make(_ format: String) -> DateFormatter {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.calendar = calendar
                df.timeZone = calendar.timeZone
                df.dateFormat = format
                return df
            }
            dayF = make("MMM d"); weekdayF = make("EEE MMM d, yyyy"); timeF = make("h:mm a")
        }

        func day(_ d: Date) -> String { dayF.string(from: d) }
        func weekdayDay(_ d: Date) -> String { weekdayF.string(from: d) }
        func time(_ d: Date) -> String { timeF.string(from: d) }
        func range(_ a: Date, _ b: Date) -> String { calendar.isDate(a, inSameDayAs: b) ? day(a) : "\(day(a)) – \(day(b))" }
        func hour(_ h: Int) -> String { h == 0 ? "12 am" : h < 12 ? "\(h) am" : h == 12 ? "12 pm" : "\(h - 12) pm" }
        func num(_ v: Double) -> String {
            let r = (v * 10).rounded() / 10
            return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        }
        func ratio(_ r: Double) -> String { String(format: "%.2f×", r) }
    }
}
