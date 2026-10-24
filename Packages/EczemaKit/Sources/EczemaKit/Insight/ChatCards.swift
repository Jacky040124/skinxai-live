import Foundation

// What the chat draws for Claude's display tools and questions, read from the model's arguments. The model can
// send anything (missing fields, odd types, dates outside the 14 nights), so every field has a safe default.

/// `show_timeline`: the 14 nights with one change marked on them.
public struct ChatTimeline: Hashable, Sendable {
    /// Minutes of scratching per night, oldest first.
    public var minutes: [Int]
    /// Nights above 1.5 × usual (the orange bars).
    public var hot: [Bool]
    /// The marked night, if `marker_date` is one of the 14.
    public var marker: Int?
    /// Claude's label for the change ("Started new body wash").
    public var label: String
    /// A small picture for the label ("🧴" for a body wash), if one fits.
    public var emoji: String?
    /// Claude's sentence about the timing.
    public var note: String?
    /// "Oct 10": the first night.
    public var startLabel: String
    /// "Oct 20": the marked night.
    public var markerLabel: String?

    public init(arguments: [String: Any], now: Date = Date(), calendar: Calendar = .current) {
        minutes = StageStory.nights
        hot = StageStory.nights.indices.map(StageStory.isFlare)
        let date = (arguments["marker_date"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        marker = StageStory.night(iso: String(date.prefix(10)), now: now, calendar: calendar)
        label = Self.text(arguments["marker_label"]) ?? "Change"
        emoji = Self.emoji(for: label)
        note = Self.text(arguments["note"])
        startLabel = StageStory.monthDay(StageStory.nightDate(0, now: now, calendar: calendar), calendar: calendar)
        markerLabel = marker.map { StageStory.monthDay(StageStory.nightDate($0, now: now, calendar: calendar), calendar: calendar) }
    }

    /// A picture for a change, by what it names.
    static func emoji(for label: String) -> String? {
        let l = label.lowercased()
        if ["wash", "soap", "shampoo", "lotion", "cream", "gel", "cleanser", "product"].contains(where: l.contains) { return "🧴" }
        if l.contains("detergent") || l.contains("laundry") { return "🧺" }
        if l.contains("humid") || l.contains("dry") { return "💧" }
        if l.contains("exam") || l.contains("stress") || l.contains("midterm") { return "📚" }
        if l.contains("sock") || l.contains("wool") { return "🧦" }
        return nil
    }

    static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// `show_product`: the suspected product, matched to his orders for the date and the ingredient list.
public struct ChatProduct: Hashable, Sendable {
    public struct Ingredient: Hashable, Sendable {
        public var name: String
        /// A common contact allergen Claude pointed at.
        public var flagged: Bool
    }

    /// "Body wash, 18 fl oz" (the order's item when it matches Claude's generic name, else Claude's name).
    public var title: String
    /// He had never bought it before.
    public var firstTime: Bool
    /// "Ordered Mon Oct 19".
    public var ordered: String?
    public var ingredients: [Ingredient]
    public var note: String?

    public var hasFlags: Bool { ingredients.contains { $0.flagged } }

    public init(arguments: [String: Any], now: Date = Date(), calendar: Calendar = .current) {
        let name = ChatTimeline.text(arguments["name"]) ?? "Product"
        let key = Self.norm(name.components(separatedBy: ",")[0])
        let purchase = (arguments["purchase_date"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let orders = StageStory.orders(now: now, calendar: calendar)
        let order = orders.first { StageStory.iso($0.date, calendar: calendar) == String(purchase.prefix(10)) && $0.category == "personal care" }
            ?? orders.first { !key.isEmpty && Self.norm($0.item.components(separatedBy: ",")[0]) == key }

        let flagged = (arguments["flagged_ingredients"] as? [Any] ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        func matches(_ a: String, _ b: String) -> Bool {
            let x = Self.norm(a), y = Self.norm(b)
            return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
        }
        var list = (order?.ingredients ?? []).map { ing in Ingredient(name: ing, flagged: flagged.contains { matches(ing, $0) }) }
        for f in flagged where !list.contains(where: { $0.flagged && matches($0.name, f) }) {
            list.append(Ingredient(name: f, flagged: true))
        }

        title = order.flatMap { Self.norm($0.item.components(separatedBy: ",")[0]) == key ? $0.item : nil } ?? name
        firstTime = order?.boughtBefore == false
        let when = StageStory.date(iso: purchase, calendar: calendar) ?? order?.date
        ordered = when.map { "Ordered \(StageStory.weekday($0, short: true, calendar: calendar)) \(StageStory.monthDay($0, calendar: calendar))" }
        ingredients = list
        note = ChatTimeline.text(arguments["note"])
    }

    /// chat.js `norm`: lowercase letters only, without a final "s" ("Body washes" → "bodywashe").
    static func norm(_ text: String) -> String {
        let az: ClosedRange<Unicode.Scalar> = "a"..."z"
        var letters = String(text.lowercased().unicodeScalars.filter { az.contains($0) }.map(Character.init))
        if letters.hasSuffix("s") { letters.removeLast() }
        return letters
    }
}

/// `ask_user`: one short question with 2–3 answers.
public struct ChatQuestion: Hashable, Sendable {
    public var question: String
    public var options: [String]

    public init(arguments: [String: Any]) {
        question = ChatTimeline.text(arguments["question"]) ?? "Can you tell me more?"
        options = Array((arguments["options"] as? [Any] ?? [])
            .map { ($0 as? String) ?? "\($0)" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4))
    }
}

/// `show_conclusion`: the most likely cause, how sure, what was ruled out and a simple test.
public struct ChatConclusion: Hashable, Sendable {
    public struct RuledOut: Hashable, Sendable {
        public var item: String
        public var reason: String?
    }

    public var cause: String
    /// "Low", "Medium", "High" (or "Medium–high").
    public var confidence: String
    /// How full the confidence bar is, 0…1.
    public var confidenceFill: Double
    public var ruledOut: [RuledOut]
    public var nextStep: String?

    public init(arguments: [String: Any]) {
        cause = ChatTimeline.text(arguments["cause"]) ?? "Not sure yet"
        let level = (arguments["confidence"] as? String ?? "").lowercased()
        switch (level.contains("low"), level.contains("medium") || level.contains("moderate"), level.contains("high")) {
        case (_, true, true): (confidence, confidenceFill) = ("Medium–high", 0.72)
        case (true, true, _): (confidence, confidenceFill) = ("Low–medium", 0.42)
        case (_, _, true): (confidence, confidenceFill) = ("High", 0.84)
        case (true, _, _): (confidence, confidenceFill) = ("Low", 0.3)
        default: (confidence, confidenceFill) = ("Medium", 0.58)
        }
        ruledOut = Array((arguments["ruled_out"] as? [Any] ?? []).compactMap { entry -> RuledOut? in
            if let item = ChatTimeline.text(entry) { return RuledOut(item: item, reason: nil) }
            guard let object = entry as? [String: Any], let item = ChatTimeline.text(object["item"]) else { return nil }
            return RuledOut(item: item, reason: ChatTimeline.text(object["reason"]))
        }.prefix(6))
        nextStep = ChatTimeline.text(arguments["next_step"])
    }
}
