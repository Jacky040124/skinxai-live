import SwiftUI
import EczemaKit

/// What the event sheet says about one event: the item, its purchase date, the ingredient (or material)
/// list with the common contact allergens lit, and how scratching went in the 4 nights after the
/// purchase against his usual. Only what the app can read: the order (date, item, ingredients), not
/// when he used it. Exams and late workouts (calendar, Apple Health) compare nights with and without.
struct TrendsEventDetail {
    struct Fact: Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    let event: TrendsEvent
    let title: String
    /// "PERSONAL CARE · AMAZON ORDER"
    let category: String
    let firstTime: Bool
    let facts: [Fact]
    /// "Ingredients", "Material"
    let listTitle: String
    let ingredients: [(name: String, flagged: Bool)]
    let impact: StageHistory.Impact
    /// A bought item: the nights after its order date against his usual (instead of `impact`).
    let purchase: TrendsPurchase?
    /// "4 NIGHTS · OCT 6–9"
    let afterText: String
    /// "Bought the same day as the FreshMeadow Spring Bloom Detergent (Oct 5)…"
    let note: String?

    /// Contact allergens lit in the lists.
    static let irritants: Set<String> = ["Fragrance (Parfum)", "Methylisothiazolinone", "Fragrance", "Wool, 100%"]

    /// The scented sample's label (trial size).
    static let detergentIngredients = ["Water", "Sodium Laureth Sulfate", "Alcohol Ethoxylate", "Sodium Citrate",
                                       "Fragrance", "Protease (enzyme)", "Optical brightener"]

    init(_ e: TrendsEvent, now: Date = Date()) {
        let cal = TrendsStory.calendar
        let day = { (i: Int) in TrendsStory.dayText(night: i, now: now) }
        let span: String = {
            let a = StageStory.nightDate(e.start, now: now, calendar: cal)
            let b = StageStory.nightDate(e.end, now: now, calendar: cal)
            if e.end == StageStory.lastNightIndex { return "\(StageStory.monthDay(a, calendar: cal))–now" }
            return e.start == e.end ? StageStory.monthDay(a, calendar: cal) : StageStory.monthDayRange(a, b, calendar: cal)
        }()
        let nights = e.end - e.start + 1
        let orders = StageStory.orders(now: now, calendar: cal)
        let p = TrendsPurchase(e.kind)
        func order(_ item: String) -> StageStory.Order? { orders.first { $0.item == item } }
        func ordered(_ o: StageStory.Order?) -> String {
            o.map { "\(StageStory.weekday($0.date, short: true, calendar: cal)) \(StageStory.monthDay($0.date, calendar: cal))" } ?? "—"
        }
        event = e
        impact = StageHistory.impact(e.factor)
        purchase = p
        afterText = p.map { p in
            let a = StageStory.nightDate(p.nights.lowerBound, now: now, calendar: cal)
            let b = StageStory.nightDate(p.nights.upperBound, now: now, calendar: cal)
            return "\(p.nights.count) NIGHTS · \(StageStory.monthDayRange(a, b, calendar: cal).uppercased())"
        } ?? ""
        let twin = p?.sameDay.first.flatMap { k in TrendsEvent.all.first { $0.kind == k } }
        note = twin.map {
            "Bought the same day as the \($0.name) (\(span)): same nights after."
        }
        switch e.kind {
        case .bodywash:
            let o = StageStory.bodyWashOrder(now: now, calendar: cal)
            title = e.name
            category = "\(o.category) · Amazon order"
            firstTime = !o.boughtBefore
            facts = [.init(label: "Bought", value: ordered(o)),
                     .init(label: "Item", value: o.item)]
            listTitle = "Ingredients"
            ingredients = (o.ingredients ?? StageStory.bodyWashIngredients).map { ($0, Self.irritants.contains($0)) }
        case .sweater:
            let o = order(StageHistory.woolSweaterItem)
            title = e.name
            category = "\(o?.category ?? "clothing") · Amazon order"
            firstTime = !(o?.boughtBefore ?? false)
            facts = [.init(label: "Bought", value: ordered(o)),
                     .init(label: "Item", value: o?.item ?? StageHistory.woolSweaterItem),
                     .init(label: "Note", value: "Your first wool sweater")]
            listTitle = "Material"
            ingredients = [("Wool, 100%", true)]
        case .detergent:
            let o = order(StageHistory.sampleDetergentItem)
            title = e.name
            category = "\(o?.category ?? "household") · Amazon order"
            firstTime = !(o?.boughtBefore ?? false)
            facts = [.init(label: "Bought", value: ordered(o)),
                     .init(label: "Item", value: o?.item ?? StageHistory.sampleDetergentItem),
                     .init(label: "Note", value: "Scented sample")]
            listTitle = "Ingredients"
            ingredients = Self.detergentIngredients.map { ($0, Self.irritants.contains($0)) }
        case .exams:
            let midterms = StageStory.examNights == e.start...e.end
            title = midterms ? "Midterm exams" : "Exam week"
            category = "Calendar"
            firstTime = false
            facts = [.init(label: "When", value: span),
                     .init(label: "Length", value: "\(nights) days"),
                     .init(label: "Note", value: midterms ? "CS 61B, Math 54 · stressful week" : "Quizzes and a paper")]
            listTitle = ""
            ingredients = []
        case .gym:
            title = "Late workout"
            category = "Apple Health · workout"
            firstTime = false
            facts = [.init(label: "When", value: "\(day(e.start)), evening"),
                     .init(label: "All time", value: "\(StageHistory.nights.filter(\.gym).count) late workouts in \(StageHistory.count) nights")]
            listTitle = ""
            ingredients = []
        }
    }
}

/// The sheet behind a purchase icon on the chart (or an event, by launch argument).
struct TrendsEventSheet: View {
    let detail: TrendsEventDetail
    let onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                header.riseIn(0.05, distance: reduceMotion ? 0 : 12)
                facts.riseIn(0.12, distance: reduceMotion ? 0 : 12)
                if !detail.ingredients.isEmpty {
                    ingredients.riseIn(0.19, distance: reduceMotion ? 0 : 12)
                }
                Group {
                    if let p = detail.purchase { afterPurchase(p) } else { impact }
                }
                .riseIn(0.26, distance: reduceMotion ? 0 : 12)
                ask.riseIn(0.33, distance: reduceMotion ? 0 : 12)
            }
            .padding(.horizontal, Twin.Space.screen)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Twin.Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Twin.Radius.dialog)
        .presentationBackground(Twin.Palette.paper)
        .onAppear { lit = true }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            TwinIconView(emoji: detail.event.emoji, size: 32)
                .frame(width: 54, height: 54)
                .sticker(detail.event.isProduct ? Twin.Palette.pink : Twin.Palette.cream, radius: Twin.Radius.control)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: detail.category)
                Text(detail.title)
                    .font(Twin.Typeface.title)
                    .foregroundStyle(Twin.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if detail.firstTime {
                    Sticker(text: "First time", icon: "sparkles", fill: Twin.Palette.yellow)
                        .padding(.top, 2)
                        .modifier(TodayStamp(delay: 0.35))
                }
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 32, height: 32)
                    .sticker(Twin.Palette.paper, radius: Twin.Radius.control)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            ForEach(Array(detail.facts.enumerated()), id: \.element.id) { k, fact in
                if k > 0 { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(fact.label.uppercased())
                        .font(Twin.Typeface.mono(10, bold: true))
                        .tracking(0.4)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .frame(width: 92, alignment: .leading)
                    Text(fact.value)
                        .font(Twin.Typeface.sans(15, .medium))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Twin.Space.l)
        .padding(.vertical, 4)
        .twinCard(fill: Twin.Palette.cream, padding: 0)
    }

    private var ingredients: some View {
        let flagged = detail.ingredients.filter(\.flagged).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: detail.listTitle)
                Spacer()
                Text("\(detail.ingredients.count) LISTED")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            TrendsFlow(spacing: 5, lineSpacing: 5) {
                ForEach(Array(detail.ingredients.enumerated()), id: \.offset) { k, item in
                    chip(item.name, flagged: item.flagged && lit)
                        .animation(reduceMotion ? .easeOut(duration: 0.2)
                                   : Twin.Motion.bouncy.delay(0.5 + Double(detail.ingredients.prefix(k).filter(\.flagged).count) * 0.22),
                                   value: lit)
                }
            }
            if flagged > 0 {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Twin.Palette.orange)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                        .frame(width: 10, height: 10)
                    Text(flagged == 1 ? "a common contact allergen" : "\(flagged) common contact allergens")
                        .font(Twin.Typeface.sans(12))
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
            }
        }
        .twinCard()
    }

    private func chip(_ name: String, flagged: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        return Text(name)
            .font(Twin.Typeface.sans(13, flagged ? .bold : .regular))
            .foregroundStyle(flagged ? Twin.Palette.ink : Twin.Palette.inkMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(flagged ? Twin.Palette.orange : Color.clear, in: shape)
            .overlay(shape.strokeBorder(flagged ? Twin.Palette.ink : Twin.Palette.hairline,
                                        lineWidth: flagged ? Twin.Stroke.ink : Twin.Stroke.hairline))
    }

    private var impact: some View {
        let i = detail.impact
        let scale = max(30, max(i.withMinutes, i.withoutMinutes).rounded(.up))
        let strongish = i.verdict == .strong || i.verdict == .possible
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Scratching")
                Spacer()
                Text("MIN / NIGHT")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(signed(i.roundedDifference))
                        .font(Twin.Typeface.sans(40, .bold))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text("min")
                        .font(Twin.Typeface.sans(15, .medium))
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
                .foregroundStyle(Twin.Palette.ink)
                Spacer(minLength: 6)
            }
            VStack(spacing: 6) {
                bar("With it", nights: "\(i.withNights) NIGHTS", value: i.withMinutes, scale: scale,
                    fill: strongish ? Twin.Palette.orange : (i.verdict == .weak ? Twin.Palette.orangeSoft : Twin.Palette.ink.opacity(0.32)),
                    edged: i.verdict != .none, delay: 0.4)
                bar("Without", nights: "\(i.withoutNights) NIGHTS", value: i.withoutMinutes, scale: scale,
                    fill: Twin.Palette.ink.opacity(0.15), edged: false, delay: 0.5)
            }
            Text("Average minutes per night, on the nights outside the other flares.")
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }

    /// A bought item: "4 nights after buying: 25 min vs usual 12" and the two bars.
    private func afterPurchase(_ p: TrendsPurchase) -> some View {
        let scale = max(30, max(p.afterMinutes, Double(p.usual)).rounded(.up))
        let after = Int(p.afterMinutes.rounded())
        let strongish = p.verdict == .strong || p.verdict == .possible
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "After buying it")
                Spacer()
                Text("MIN / NIGHT")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(signed(p.difference))
                        .font(Twin.Typeface.sans(40, .bold))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text("min")
                        .font(Twin.Typeface.sans(15, .medium))
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
                .foregroundStyle(Twin.Palette.ink)
                Spacer(minLength: 6)
            }
            (Text("\(p.nights.count) nights after buying: ").font(Twin.Typeface.sans(15, .bold))
                + Text("\(after) min vs usual \(p.usual)").font(Twin.Typeface.sans(15)))
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                bar("After", nights: detail.afterText, value: p.afterMinutes, scale: scale,
                    fill: strongish ? Twin.Palette.orange : (p.verdict == .weak ? Twin.Palette.orangeSoft : Twin.Palette.ink.opacity(0.32)),
                    edged: p.verdict != .none, delay: 0.4, labelWidth: 112)
                bar("Usual", nights: "YOUR NORMAL", value: Double(p.usual), scale: scale,
                    fill: Twin.Palette.ink.opacity(0.15), edged: false, delay: 0.5, labelWidth: 112)
            }
            if let note = detail.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.top, 2)
                    Text(note)
                        .font(Twin.Typeface.sans(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Twin.Palette.orangeSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                    .strokeBorder(Twin.Palette.ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            Text("Average of the \(p.nights.count) nights after the order date.")
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }

    private func bar(_ label: String, nights: String, value: Double, scale: Double, fill: Color, edged: Bool, delay: Double,
                     labelWidth: CGFloat = 66) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(Twin.Typeface.sans(13, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Text(nights)
                    .font(Twin.Typeface.mono(9))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: labelWidth, alignment: .leading)
            GeometryReader { g in
                let shape = UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous)
                HStack(spacing: 6) {
                    shape.fill(fill)
                        .overlay { if edged { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
                        .frame(width: max(3, CGFloat(value / scale) * (g.size.width - 34)))
                        .scaleEffect(x: lit || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                        .animation(reduceMotion ? nil : Twin.Motion.spring.delay(delay), value: lit)
                    Text("\(Int(value.rounded()))")
                        .font(Twin.Typeface.mono(12, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize()
                }
            }
            .frame(height: 16)
        }
    }

    private var ask: some View {
        Button {
            dismiss()
            onAsk()
        } label: {
            HStack(spacing: 8) {
                Text("✶").font(.system(size: 15, weight: .bold))
                Text("Ask Claude about this")
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
            }
        }
        .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink))
        .accessibilityHint("Opens Insight")
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "±0") }
}
