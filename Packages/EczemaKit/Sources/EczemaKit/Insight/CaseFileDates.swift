import Foundation

extension CaseFile {
    /// The same case file with every date moved by `days`: the date fields, and the "Oct 9"-style dates the
    /// model wrote in its text (the system prompt asks for that style). Demo time travel re-dates Douglas's
    /// story (today stays today), so a live analysis has to move with it to keep pointing at the same days.
    public func shiftingDates(byDays days: Int, calendar: Calendar = .current) -> CaseFile {
        guard days != 0 else { return self }
        func move(_ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        func text(_ s: String) -> String { DateText.shift(s, byDays: days, near: createdAt, calendar: calendar) }

        var c = self
        c.createdAt = move(createdAt)
        c.windowStart = move(windowStart)
        c.windowEnd = move(windowEnd)
        c.summary = text(summary)
        c.suspects = suspects.map { s in
            var s = s
            s.startedOn = s.startedOn.map(move)
            s.flareOn = s.flareOn.map(move)
            s.title = text(s.title)
            s.evidence = text(s.evidence)
            return s
        }
        c.cannotSeparate = cannotSeparate.map(text)
        c.redFlags = redFlags.map(text)
        if var plan = nextExperiment {
            plan.title = text(plan.title)
            plan.instruction = text(plan.instruction)
            c.nextExperiment = plan
        }
        return c
    }
}

/// Finds "Oct 9", "October 9", "Oct. 9" and ranges like "Oct 14–15" in free text and moves them by whole days.
enum DateText {
    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    private static let short = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let long = ["January", "February", "March", "April", "May", "June", "July", "August",
                               "September", "October", "November", "December"]

    private static let pattern = try! NSRegularExpression(pattern:
        #"\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)(\.?)(\s+)(\d{1,2})(?!\d)(?:(\s*[–-]\s*)(\d{1,2})(?!\d))?"#)

    /// `text` with each date moved by `days`. The year is the one that puts the date nearest `reference`.
    static func shift(_ text: String, byDays days: Int, near reference: Date, calendar: Calendar) -> String {
        guard days != 0, !text.isEmpty else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let token = group(1), let dayText = group(4), let day = Int(dayText),
                  let month = months[String(token.prefix(3)).lowercased()],
                  let start = date(month: month, day: day, near: reference, calendar: calendar),
                  let movedStart = calendar.date(byAdding: .day, value: days, to: start) else { continue }
            let full = token.count > 4 || token == "June" || token == "July"
            let dot = group(2) ?? ""
            let space = group(3) ?? " "
            var replacement = name(of: movedStart, full: full, calendar: calendar) + dot + space
                + "\(calendar.component(.day, from: movedStart))"
            if let separator = group(5), let endText = group(6), let endDay = Int(endText) {
                // "Oct 14–15": the end is in the same month, or the next one when it is smaller.
                var endMonth = month
                if endDay < day { endMonth = month % 12 + 1 }
                if let end = date(month: endMonth, day: endDay, near: start, calendar: calendar),
                   let movedEnd = calendar.date(byAdding: .day, value: days, to: end) {
                    let sameMonth = calendar.component(.month, from: movedEnd) == calendar.component(.month, from: movedStart)
                    replacement += separator + (sameMonth ? "" : name(of: movedEnd, full: full, calendar: calendar) + dot + " ")
                        + "\(calendar.component(.day, from: movedEnd))"
                } else {
                    replacement += separator + endText
                }
            }
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + replacement
            cursor = match.range.location + match.range.length
        }
        guard cursor > 0 else { return text }
        return out + ns.substring(from: cursor)
    }

    private static func name(of date: Date, full: Bool, calendar: Calendar) -> String {
        let m = calendar.component(.month, from: date) - 1
        return full ? long[m] : short[m]
    }

    /// The date with that month and day nearest `reference` (last, this or next year); nil if it doesn't exist.
    private static func date(month: Int, day: Int, near reference: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: reference)
        let candidates = (year - 1...year + 1).compactMap { y -> Date? in
            let comps = DateComponents(year: y, month: month, day: day)
            guard let d = calendar.date(from: comps), calendar.component(.day, from: d) == day else { return nil }
            return d
        }
        return candidates.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
    }
}
