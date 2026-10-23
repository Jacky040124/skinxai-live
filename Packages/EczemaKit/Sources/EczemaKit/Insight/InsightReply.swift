import Foundation

/// Turns the model's reply text into a `CaseFile`.
///
/// Robust to what models actually send: code fences, text or `<think>` blocks around the JSON, a wrapping
/// object, snake_case or camelCase keys, numbers or booleans sent as strings, a string where a list was
/// asked for, "Low–Medium"/"low_medium"/"moderate" confidences, missing fields and extra suspects.
public enum InsightReply {
    public enum DecodeError: Error, Equatable, Sendable {
        case noJSON
        case nothingUseful
    }

    /// Everything needed to turn reply text into a case file.
    public struct Context: Sendable {
        public var stats: InsightStats
        public var number: Int
        public var createdAt: Date
        public var producedBy: String
        public init(stats: InsightStats, number: Int, createdAt: Date, producedBy: String) {
            self.stats = stats; self.number = number; self.createdAt = createdAt; self.producedBy = producedBy
        }
    }

    public static let maxSuspects = 3

    public static func caseFile(from reply: String, context: Context) throws -> CaseFile {
        guard let object = jsonObject(in: reply) else { throw DecodeError.noJSON }
        let root = Lenient(unwrap(object))
        let stats = context.stats

        var suspects: [Suspect] = []
        for raw in root.list("suspects", "suspect", "triggers", "candidates") {
            guard let s = suspect(from: raw, stats: stats), !suspects.contains(where: { $0.title.lowercased() == s.title.lowercased() })
            else { continue }
            suspects.append(s)
            if suspects.count == maxSuspects { break }
        }

        let redFlags = root.strings("red_flags", "redFlags", "warning_signs", "warnings")
        let cannotSeparate = root.strings("cannot_separate", "cannotSeparate", "cant_separate", "confounders")
        var summary = root.string("plain_summary", "summary", "plainSummary", "plain_language_summary") ?? ""
        if summary.isEmpty, let top = suspects.first {
            summary = "The most likely trigger is \(top.title.lowercased()) (\(top.confidence.label.lowercased()) confidence)."
        }
        guard !summary.isEmpty || !redFlags.isEmpty else { throw DecodeError.nothingUseful }
        if summary.isEmpty { summary = "Some of what you logged needs a doctor's eyes today." }

        let patternFound = root.bool("pattern_found", "patternFound") ?? !suspects.isEmpty
        let plan = experiment(from: root, topSuspect: suspects.first)

        return CaseFile(number: context.number, createdAt: context.createdAt, windowStart: stats.windowStart,
                        windowEnd: stats.windowEnd, patternFound: patternFound, summary: summary, suspects: suspects,
                        cannotSeparate: cannotSeparate, nextExperiment: plan, redFlags: redFlags,
                        producedBy: context.producedBy)
    }

    // MARK: - JSON extraction

    /// Finds the JSON object in a reply (fences, think-blocks and chatter around it are ignored).
    public static func jsonObject(in reply: String) -> Any? {
        var text = reply
        // Drop reasoning blocks some models inline.
        while let open = text.range(of: "<think>"), let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        var candidates: [String] = []
        // Fenced blocks first (```json ... ```).
        var rest = text[...]
        while let open = rest.range(of: "```") {
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "```") else { break }
            var body = afterOpen[..<close.lowerBound]
            if let newline = body.firstIndex(of: "\n"), !body[..<newline].contains("{") { body = body[body.index(after: newline)...] }
            candidates.append(String(body))
            rest = afterOpen[close.upperBound...]
        }
        candidates.append(text)
        for c in candidates {
            if let obj = parse(c) { return obj }
            // The outermost {...} (or [...]) inside the text.
            if let start = c.firstIndex(of: "{"), let end = c.lastIndex(of: "}"), start < end, let obj = parse(String(c[start...end])) {
                return obj
            }
            if let start = c.firstIndex(of: "["), let end = c.lastIndex(of: "]"), start < end, let obj = parse(String(c[start...end])) {
                return obj
            }
        }
        return nil
    }

    private static func parse(_ s: String) -> Any? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, first == "{" || first == "[", let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let a = obj as? [Any] { return a.first { $0 is [String: Any] } }
        return obj as? [String: Any]
    }

    /// `{"case_file": {...}}` → `{...}`
    private static func unwrap(_ object: Any) -> [String: Any] {
        guard var dict = object as? [String: Any] else { return [:] }
        let known: Set<String> = ["suspects", "plain_summary", "summary", "pattern_found", "red_flags", "next_experiment"]
        for _ in 0..<2 where Set(dict.keys).isDisjoint(with: known) {
            guard dict.count == 1, let inner = dict.values.first as? [String: Any] else { break }
            dict = inner
        }
        return dict
    }

    // MARK: - Fields

    static func suspect(from raw: Any, stats: InsightStats) -> Suspect? {
        let s: Lenient
        if let dict = raw as? [String: Any] {
            s = Lenient(dict)
        } else if let text = raw as? String, !text.isEmpty {
            s = Lenient(["trigger": text])
        } else {
            return nil
        }
        guard var title = s.string("trigger", "title", "name", "exposure", "suspect") else { return nil }
        let lowered = title.lowercased()
        // Symptoms and conditions are not suspects (schema misuse seen in testing).
        if ["infection", "eczema", "dermatitis", "impetigo", "red flag"].contains(where: lowered.contains) { return nil }

        let kind = ExposureKind.parse(s.string("kind", "category", "type")) ?? match(title, in: stats)?.kind ?? ExposureKind.guess(from: title)
        let stat = match(title, in: stats, kind: kind)
        if title.count > 48, let stat { title = stat.title }
        title = title.prefix(1).uppercased() + title.dropFirst()

        let confidence = Confidence.parse(s.string("confidence", "level", "likelihood")) ?? .low
        let lag = lagText(s.string("lag_days", "lag", "lagDays", "delay"))
            ?? stat?.bestLag.map { lagText("about \($0)") ?? "" } ?? ""
        let evidence = s.string("evidence", "why", "reason", "explanation") ?? ""

        var startedOn: Date?
        var flareOn: Date?
        if let stat {
            startedOn = stat.firstDay
            if let flare = stats.currentFlare, stat.onset == .beforeFlare || stat.onset == .longBefore { flareOn = flare.start }
        }
        return Suspect(kind: kind, title: title, confidence: confidence, lag: lag, evidence: evidence,
                       startedOn: startedOn, flareOn: flareOn)
    }

    /// The exposure in the stats that a model's trigger name refers to.
    static func match(_ name: String, in stats: InsightStats, kind: ExposureKind? = nil) -> InsightStats.ExposureStat? {
        let words = significantWords(name)
        var best: (InsightStats.ExposureStat, Int)?
        for e in stats.exposures {
            var score = words.intersection(significantWords(e.title)).count * 2
            if e.kind == kind { score += 3 }
            if words.intersection(significantWords(e.kind.label)).count > 0 { score += 1 }
            if score > (best?.1 ?? 0) { best = (e, score) }
        }
        guard let best, best.1 >= 2 else { return nil }
        return best.0
    }

    private static func significantWords(_ s: String) -> Set<String> {
        let stop: Set<String> = ["new", "the", "a", "an", "and", "of", "your", "my", "in", "to", "with", "short", "very"]
        return Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 && !stop.contains($0) })
    }

    /// "about 2" → "about 2 days", "0-1" → "0–1 day", "2" → "2 days", "about 2 days" stays.
    static func lagText(_ raw: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !["n/a", "na", "unknown", "none", "-", "—"].contains(t.lowercased()) else { return nil }
        t = t.replacingOccurrences(of: #"(\d)\s*-\s*(\d)"#, with: "$1–$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\d)\s+to\s+(\d)"#, with: "$1–$2", options: .regularExpression)
        let lower = t.lowercased()
        if lower.contains("day") || lower.contains("hour") || lower.contains("week") { return t }
        guard let last = t.last, last.isNumber else { return t }
        let singular = t.hasSuffix("–1") || t == "1" || lower.hasSuffix(" 1")
        return t + (singular ? " day" : " days")
    }

    static func experiment(from root: Lenient, topSuspect: Suspect?) -> ExperimentPlan? {
        let keys = ["next_experiment", "nextExperiment", "experiment", "next_step"]
        if let dict = root.dict(keys) {
            let e = Lenient(dict)
            let instruction = e.string("instruction", "instructions", "how", "description", "plan") ?? ""
            let title = e.string("title", "name", "action") ?? title(fromInstruction: instruction) ?? ""
            guard !title.isEmpty || !instruction.isEmpty else { return nil }
            let length = e.int("length_days", "lengthDays", "days", "duration_days") ?? 10
            let kind = ExposureKind.parse(e.string("kind", "trigger", "trigger_kind")) ?? topSuspect?.kind
            return ExperimentPlan(title: title.isEmpty ? (topSuspect.map { "Pause \($0.title.lowercased())" } ?? "One change") : title,
                                  instruction: instruction.isEmpty ? title : instruction,
                                  trigger: kind, lengthDays: min(max(length, 5), 21))
        }
        guard let text = root.string(keys), !text.isEmpty else { return nil }
        let days = firstNumber(in: text).map { min(max($0, 5), 21) } ?? 10
        return ExperimentPlan(title: title(fromInstruction: text) ?? "One change at a time", instruction: text,
                              trigger: topSuspect?.kind, lengthDays: days)
    }

    /// "Stop the scented body wash for 10 days and ..." → "Stop the scented body wash".
    static func title(fromInstruction text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        for sep in [". ", ": ", "; ", ", ", " for ", " and ", " - ", " — ", " – ", "("] {
            if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) }
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .")).trimmingCharacters(in: .whitespaces)
        let words = t.split(separator: " ")
        if words.count > 6 { t = words.prefix(6).joined(separator: " ") }
        return t.isEmpty ? nil : t.prefix(1).uppercased() + t.dropFirst()
    }

    private static func firstNumber(in text: String) -> Int? {
        guard let r = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[r])
    }
}

// MARK: - Lenient dictionary access

struct Lenient {
    let dict: [String: Any]
    init(_ dict: [String: Any]) { self.dict = dict }

    private func value(_ keys: [String]) -> Any? {
        for k in keys { if let v = dict[k], !(v is NSNull) { return v } }
        // Case/underscore-insensitive fallback.
        let wanted = Set(keys.map(Lenient.squash))
        return dict.first { wanted.contains(Lenient.squash($0.key)) && !($0.value is NSNull) }?.value
    }
    private static func squash(_ k: String) -> String { k.lowercased().filter { $0.isLetter || $0.isNumber } }

    func string(_ keys: String...) -> String? { string(keys) }
    func string(_ keys: [String]) -> String? {
        switch value(keys) {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber: return n.stringValue
        case let a as [Any]:
            let joined = a.compactMap { $0 as? String }.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        default: return nil
        }
    }
    func strings(_ keys: String...) -> [String] {
        switch value(keys) {
        case let a as [Any]:
            return a.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let d = item as? [String: Any] { return Lenient(d).string("text", "description", "note", "reason", "flag") }
                return nil
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !["none", "n/a", "no"].contains($0.lowercased()) }
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || ["none", "n/a", "no", "[]"].contains(t.lowercased()) ? [] : [t]
        default: return []
        }
    }
    func list(_ keys: String...) -> [Any] {
        switch value(keys) {
        case let a as [Any]: return a
        case let d as [String: Any]: return [d]
        case let s as String where !s.isEmpty: return [s]
        default: return []
        }
    }
    func dict(_ keys: [String]) -> [String: Any]? { value(keys) as? [String: Any] }
    func bool(_ keys: String...) -> Bool? {
        switch value(keys) {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "yes", "1"].contains(s.lowercased()) ? true : ["false", "no", "0"].contains(s.lowercased()) ? false : nil
        default: return nil
        }
    }
    func int(_ keys: String...) -> Int? {
        switch value(keys) {
        case let n as NSNumber: return n.intValue
        case let s as String:
            guard let r = s.range(of: #"\d+"#, options: .regularExpression) else { return nil }
            return Int(s[r])
        default: return nil
        }
    }
}

// MARK: - Parsing model words into our enums

extension Confidence {
    /// "Low–Medium", "low_medium", "low-to-medium", "moderate", "HIGH" …
    public static func parse(_ raw: String?) -> Confidence? {
        guard let raw else { return nil }
        if let d = Double(raw.trimmingCharacters(in: .whitespaces)) {
            let p = d > 1 ? d / 100 : d          // 0.6 or 60
            return p >= 0.75 ? .high : p >= 0.5 ? .medium : p >= 0.3 ? .lowMedium : .low
        }
        let t = raw.lowercased().filter { $0.isLetter }
        if t.isEmpty { return nil }
        if t.hasPrefix("low") && (t.contains("med") || t.contains("moderate")) { return .lowMedium }
        if t.hasPrefix("low") || t.hasPrefix("verylow") || t.hasPrefix("weak") { return .low }
        if t.hasPrefix("med") || t.hasPrefix("moderate") { return .medium }   // "medium-high" stays medium: be humble
        if t.hasPrefix("high") || t.hasPrefix("strong") || t.hasPrefix("veryhigh") { return .high }
        return nil
    }
}

extension ExposureKind {
    /// "dryAir", "dry_air", "Dry air", "new product" …
    public static func parse(_ raw: String?) -> ExposureKind? {
        guard let raw else { return nil }
        let squashed = raw.lowercased().filter { $0.isLetter }
        return ExposureKind.allCases.first { $0.rawValue.lowercased() == squashed || $0.label.lowercased().filter(\.isLetter) == squashed }
    }

    /// Best guess from a free-text trigger name.
    public static func guess(from text: String) -> ExposureKind {
        let t = text.lowercased()
        let table: [(ExposureKind, [String])] = [
            (.detergent, ["detergent", "laundry", "fabric softener"]),
            (.newProduct, ["wash", "soap", "lotion", "cream", "shampoo", "product", "cosmetic", "perfume", "fragrance", "moisturizer", "sunscreen"]),
            (.dryAir, ["humid", "dry air", "heating", "dry weather", "dry indoor", "cold weather"]),
            (.stress, ["stress", "exam", "sleep", "anxiety"]),
            (.dairy, ["dairy", "milk", "cheese", "yogurt"]),
            (.nuts, ["nut", "peanut"]),
            (.seafood, ["seafood", "shrimp", "fish", "shellfish", "prawn"]),
            (.gluten, ["gluten", "wheat", "bread", "pasta", "pizza"]),
            (.alcohol, ["alcohol", "wine", "beer"]),
            (.sweat, ["sweat", "gym", "workout", "exercise", "running", "heat"]),
            (.pet, ["pet", "dog", "cat"]),
            (.pool, ["pool", "chlorine", "swim"]),
            (.wool, ["wool", "sweater", "scarf"]),
            (.travel, ["travel", "trip", "flight"]),
        ]
        return table.first { $0.1.contains(where: t.contains) }?.0 ?? .other
    }
}
