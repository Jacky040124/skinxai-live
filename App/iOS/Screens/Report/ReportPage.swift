import SwiftUI
import EczemaKit

/// The doctor report: one US Letter page (612 × 792 pt). The same view is shown in the app
/// (scaled, animated) and drawn into the PDF (`animated: false`, final state).
struct ReportPage: View {
    let facts: ReportFacts
    var animated = false

    static let size = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 36
    @State private var shown = false
    private var on: Bool { !animated || shown }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                stats.modifier(PageRise(on: on, delay: 0.15, animated: animated))
                chart.modifier(PageRise(on: on, delay: 0.3, animated: animated))
                HStack(alignment: .top, spacing: 18) {
                    suspects.frame(width: 312, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 14) {
                        vitals
                        changes
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .modifier(PageRise(on: on, delay: 0.45, animated: animated))
                testBlock.modifier(PageRise(on: on, delay: 0.6, animated: animated))
                Spacer(minLength: 0)
                footer.modifier(PageRise(on: on, delay: 0.7, animated: animated))
            }
            .padding(.horizontal, margin)
            .padding(.top, 13)
            .padding(.bottom, 22)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 0.01)) { shown = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ECZEMA TWIN · SCRATCH & TRIGGER REPORT")
                    .font(Twin.Typeface.mono(7.5, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Twin.Palette.frameInk)
                Text(facts.name.isEmpty ? "Patient" : facts.name)
                    .font(Twin.Typeface.sans(24, .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Twin.Palette.ink)
                Text("\(range) · \(facts.dayCount) days · scratching measured by Apple Watch")
                    .font(Twin.Typeface.sans(9.5))
                    .foregroundStyle(Twin.Palette.ink.opacity(0.75))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("GENERATED")
                    .font(Twin.Typeface.mono(7, bold: true))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.frameInk)
                Text(facts.generated.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Twin.Typeface.mono(9.5, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                if let c = facts.caseFile {
                    Text("CASE #\(c.number)")
                        .font(Twin.Typeface.mono(8, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Twin.Palette.pink)
                        .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .background(Twin.Palette.frame)
        .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.seam).frame(height: 0.75) }
    }

    private var range: String {
        let a = facts.windowStart.formatted(.dateTime.month(.abbreviated).day())
        let b = facts.windowEnd.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(a) – \(b)"
    }

    // MARK: Numbers

    private var stats: some View {
        HStack(spacing: 8) {
            stat("TODAY", value: Self.minutes(facts.todayMinutes), unit: "min",
                 note: facts.todayRatio >= 1.5 ? "\(Self.ratio(facts.todayRatio)) usual"
                     : (facts.todayRatio < 0.67 ? "below usual" : "about usual"),
                 tint: facts.todayRatio >= 1.5 ? Twin.Palette.orange : nil)
            stat("LAST 7 DAYS", value: Self.minutes(facts.weekAverage), unit: "min/day",
                 note: facts.weekChange.map { ($0 >= 0 ? "▲ " : "▼ ") + Self.percent(abs($0)) + " vs. week before" } ?? "no data the week before",
                 tint: (facts.weekChange ?? 0) > 0.5 ? Twin.Palette.orange : nil)
            stat("USUAL", value: Self.minutes(facts.usual), unit: "min/day",
                 note: facts.usualIsEstimate ? "starting estimate" : "median of calm days", tint: nil)
            stat("WORST HOURS", value: facts.worstHours ?? "—", unit: "",
                 note: "\(Self.count(facts.totalEpisodes, "episode")), \(facts.intenseEpisodes) intense in 7 days", tint: nil)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stat(_ label: String, value: String, unit: String, note: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Twin.Typeface.mono(7, bold: true))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Twin.Typeface.sans(19, .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Twin.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit).font(Twin.Typeface.mono(7.5)).foregroundStyle(Twin.Palette.inkHint)
                }
            }
            Text(note)
                .font(Twin.Typeface.sans(7.5, .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, tint == nil ? 0 : 4)
                .padding(.vertical, tint == nil ? 0 : 1.5)
                .background(tint ?? .clear)
                .overlay { if tint != nil { Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75) } }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Twin.Palette.hairline, lineWidth: 0.75))
    }

    // MARK: Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MINUTES OF SCRATCHING PER DAY")
                    .font(Twin.Typeface.mono(7.5, bold: true))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                Spacer()
                HStack(spacing: 10) {
                    legend(color: Twin.Palette.orange, edge: true, text: "above 1.5× usual")
                    HStack(spacing: 4) {
                        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 14, y: 0)) }
                            .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                            .frame(width: 14, height: 1)
                        Text("your usual").font(Twin.Typeface.mono(7)).foregroundStyle(Twin.Palette.inkHint)
                    }
                    if facts.bars.contains(where: \.inTest) {
                        legend(color: Twin.Palette.cyanSoft, edge: false, text: "test")
                    }
                }
            }
            ReportBars(facts: facts, grown: on, animated: animated)
                .frame(height: 126)
                .overlay {
                    if facts.trackedDays < 3 {
                        Text("Only \(Self.count(facts.trackedDays, "full day")) tracked so far. Wear the watch at night to fill this chart.")
                            .font(Twin.Typeface.sans(9, .semibold))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Twin.Palette.cream)
                            .overlay(Rectangle().strokeBorder(Twin.Palette.hairline, lineWidth: 0.75))
                    }
                }
        }
    }

    private func legend(color: Color, edge: Bool, text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 8, height: 8)
                .overlay { if edge { Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75) } }
            Text(text).font(Twin.Typeface.mono(7)).foregroundStyle(Twin.Palette.inkHint)
        }
    }

    // MARK: Suspects

    private var suspects: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LIKELY TRIGGERS")
                    .font(Twin.Typeface.mono(7.5, bold: true))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                Spacer()
                Text("✶ CLAUDE")
                    .font(Twin.Typeface.mono(7, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Twin.Palette.pink)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
            }
            if let c = facts.caseFile, !c.suspects.isEmpty {
                ForEach(Array(c.suspects.prefix(3).enumerated()), id: \.offset) { i, s in
                    suspectRow(i, s)
                }
                if let note = c.cannotSeparate.first {
                    Text(note)
                        .font(Twin.Typeface.sans(8))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .padding(.leading, 6)
                        .overlay(alignment: .leading) { Rectangle().fill(Twin.Palette.orange).frame(width: 1.5) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(c.producedBy.uppercased()) · PATTERNS IN THE LOG, NOT PROOF")
                    .font(Twin.Typeface.mono(6.5))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No analysis yet. Claude ranks likely triggers once there are enough days to compare.")
                    .font(Twin.Typeface.sans(9))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func suspectRow(_ i: Int, _ s: Suspect) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text("\(i + 1)")
                    .font(Twin.Typeface.mono(8, bold: true))
                    .frame(width: 14, height: 14)
                    .background(Color.white)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
                Text(s.title)
                    .font(Twin.Typeface.sans(10.5, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(s.confidence.label.uppercased())
                    .font(Twin.Typeface.mono(6.5, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(i == 0 ? Twin.Palette.yellow : Color.white)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
            }
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Twin.Palette.fill)
                        Rectangle().fill(Twin.Palette.cyan).frame(width: g.size.width * (on ? s.confidence.score : 0))
                            .animation(animated ? Twin.Motion.fill.delay(0.7 + Double(i) * 0.12) : nil, value: on)
                    }
                }
                .frame(height: 3.5)
                Text("LAG \(s.lag.uppercased())")
                    .font(Twin.Typeface.mono(6.5))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
            }
            Text(s.evidence)
                .font(Twin.Typeface.sans(8))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(i == 0 ? Twin.Palette.yellowSoft : Color.white)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(i == 0 ? Twin.Palette.ink : Twin.Palette.hairline, lineWidth: i == 0 ? 1 : 0.75))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: Sleep & stress, what changed

    private var vitals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SLEEP & STRESS")
                .font(Twin.Typeface.mono(7.5, bold: true))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
            if facts.vitals.isEmpty {
                Text("No Apple Health data for these days.")
                    .font(Twin.Typeface.sans(8.5))
                    .foregroundStyle(Twin.Palette.inkMuted)
            } else {
                HStack {
                    Spacer()
                    Text("LAST 7 DAYS").frame(width: 64, alignment: .trailing)
                    Text("CALM DAYS").frame(width: 52, alignment: .trailing)
                }
                .font(Twin.Typeface.mono(6))
                .foregroundStyle(Twin.Palette.inkHint)
                ForEach(facts.vitals, id: \.label) { v in
                    HStack {
                        Text(v.label).font(Twin.Typeface.sans(9, .semibold)).foregroundStyle(Twin.Palette.ink)
                        Spacer()
                        Text((v.arrow.map { $0 + " " } ?? "") + v.recent)
                            .font(Twin.Typeface.mono(8.5, bold: true))
                            .foregroundStyle(Twin.Palette.ink)
                            .padding(.horizontal, v.worse ? 3 : 0)
                            .background(v.worse ? Twin.Palette.orangeSoft : .clear)
                            .lineLimit(1)
                            .frame(width: 64, alignment: .trailing)
                        Text(v.usual)
                            .font(Twin.Typeface.mono(8.5))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .lineLimit(1)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.hairline).frame(height: 0.5) }
                }
            }
        }
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT CHANGED")
                .font(Twin.Typeface.mono(7.5, bold: true))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
            if facts.changes.isEmpty {
                Text("Nothing new was logged.")
                    .font(Twin.Typeface.sans(8.5))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            ForEach(facts.changes) { c in
                HStack(alignment: .center, spacing: 7) {
                    Text(c.emoji)
                        .font(.system(size: 8.5))
                        .frame(width: 16, height: 16)
                        .background(c.automatic ? Twin.Palette.orangeSoft : Twin.Palette.pinkSoft)
                        .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(Twin.Typeface.sans(9, .semibold)).foregroundStyle(Twin.Palette.ink).lineLimit(1)
                        Text(when(c)).font(Twin.Typeface.mono(7)).foregroundStyle(Twin.Palette.inkHint)
                    }
                }
            }
        }
    }

    private func when(_ c: ReportFacts.Change) -> String {
        let from = c.from.formatted(.dateTime.month(.abbreviated).day())
        if c.ongoing { return "FROM \(from.uppercased()) · ONGOING" }
        if Calendar.current.isDate(c.from, inSameDayAs: c.to) { return from.uppercased() }
        return "\(from) – \(c.to.formatted(.dateTime.month(.abbreviated).day()))".uppercased()
    }

    // MARK: Test

    @ViewBuilder private var testBlock: some View {
        if let e = facts.experiment {
            let done = e.status == .confirmed || e.status == .notConfirmed
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(done ? "TEST RESULT" : "TEST IN PROGRESS · DAY \(min(facts.experimentDay, e.plan.lengthDays)) OF \(e.plan.lengthDays)")
                        .font(Twin.Typeface.mono(7.5, bold: true))
                        .tracking(0.6)
                        .foregroundStyle(Twin.Palette.ink.opacity(0.7))
                    Spacer()
                    if e.status == .confirmed {
                        badge("CONFIRMED", Twin.Palette.lime)
                    } else if e.status == .notConfirmed {
                        badge("NO CLEAR CHANGE", Color.white)
                    }
                }
                Text(e.plan.title)
                    .font(Twin.Typeface.sans(12, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                HStack(spacing: 14) {
                    figure("BEFORE", Self.minutes(e.baselineMinutesPerDay) + " min/day")
                    Text("→").font(Twin.Typeface.sans(11, .bold))
                    figure(done ? "DURING THE TEST" : "SO FAR", facts.experimentAfter.map { Self.minutes($0) + " min/day" } ?? "—")
                    if let change = facts.experimentChange {
                        figure("CHANGE", (change <= 0 ? "▼ " : "▲ ") + Self.percent(abs(change)))
                    }
                    Spacer()
                }
                Text(done ? resultSentence(e) : e.plan.instruction)
                    .font(Twin.Typeface.sans(8.5))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(e.status == .confirmed ? Twin.Palette.limeSoft : Twin.Palette.cyanSoft)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else if let plan = facts.caseFile?.nextExperiment {
            VStack(alignment: .leading, spacing: 3) {
                Text("SUGGESTED NEXT STEP · \(plan.lengthDays)-DAY TEST")
                    .font(Twin.Typeface.mono(7.5, bold: true))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.ink.opacity(0.7))
                Text(plan.title).font(Twin.Typeface.sans(12, .bold)).foregroundStyle(Twin.Palette.ink)
                Text(plan.instruction).font(Twin.Typeface.sans(8.5)).foregroundStyle(Twin.Palette.inkMuted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Twin.Palette.cream)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Twin.Palette.hairline, lineWidth: 0.75))
        }
        if let flags = facts.caseFile?.redFlags, !flags.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("SEE A DOCTOR TODAY").font(Twin.Typeface.mono(7.5, bold: true)).foregroundStyle(Twin.Palette.redStrong)
                ForEach(flags, id: \.self) { Text("• " + $0).font(Twin.Typeface.sans(8.5)).foregroundStyle(Twin.Palette.ink) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Twin.Palette.redSoft)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Twin.Palette.red, lineWidth: 1))
        }
    }

    private func resultSentence(_ e: Experiment) -> String {
        if e.status == .confirmed {
            let what = e.plan.trigger.map { $0 == .newProduct ? "the new product" : $0.label.lowercased() } ?? "this change"
            return "Scratching fell clearly while \(what) was paused, with everything else kept the same: a likely personal trigger. Worth confirming with a patch test."
        }
        return "Scratching did not change clearly during the test, so this is probably not the main trigger."
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Twin.Typeface.mono(6.5)).foregroundStyle(Twin.Palette.inkHint)
            Text(value).font(Twin.Typeface.sans(11, .bold)).foregroundStyle(Twin.Palette.ink)
        }
    }

    private func badge(_ text: String, _ fill: Color) -> some View {
        Text(text)
            .font(Twin.Typeface.mono(7, bold: true))
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(fill)
            .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Twin.Palette.hairline).frame(height: 0.75)
            HStack(alignment: .top, spacing: 12) {
                Text("Not a diagnosis. Scratching is estimated from wrist motion and can include other hand movements. Sleep, HRV and resting heart rate come from Apple Health; humidity and air quality from Open-Meteo. \(facts.isDemo ? "This report uses the Eczema Twin demo story." : "")")
                    .font(Twin.Typeface.sans(6.8))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineSpacing(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("PAGE 1/1")
                    .font(Twin.Typeface.mono(6.5))
                    .foregroundStyle(Twin.Palette.inkHint)
            }
        }
    }

    // MARK: Formatting

    static func minutes(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    static func ratio(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) + "×" }
    static func percent(_ v: Double) -> String { (v * 100).formatted(.number.precision(.fractionLength(0))) + "%" }
}

/// Fades a section in and lifts it 8 pt (preview only).
private struct PageRise: ViewModifier {
    let on: Bool
    let delay: Double
    let animated: Bool
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 8)
            .animation(animated ? Twin.Motion.spring.delay(delay) : nil, value: on)
    }
}

/// Daily bars with the usual line, the test period and markers where something new started.
private struct ReportBars: View {
    let facts: ReportFacts
    let grown: Bool
    let animated: Bool

    var body: some View {
        GeometryReader { g in
            let n = max(1, facts.bars.count)
            let gap: CGFloat = n > 16 ? 3 : 5
            let barW = (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let labelH: CGFloat = 12, markerH: CGFloat = 16
            let plotH = g.size.height - labelH - markerH
            let top = max(facts.usual * 1.6, facts.bars.map(\.minutes).max() ?? 1, 1)
            let usualY = markerH + plotH * (1 - facts.usual / top)
            let x: (Int) -> CGFloat = { CGFloat($0) * (barW + gap) }

            ZStack(alignment: .topLeading) {
                if let first = facts.bars.firstIndex(where: \.inTest) {
                    Rectangle()
                        .fill(Twin.Palette.cyanSoft)
                        .frame(width: x(n - 1) + barW - x(first) + gap, height: plotH + markerH)
                        .offset(x: x(first) - gap / 2)
                    Text("TEST")
                        .font(Twin.Typeface.mono(6.5, bold: true))
                        .foregroundStyle(Twin.Palette.cyanStrong)
                        .offset(x: x(first) + 2, y: 2)
                }
                ForEach(facts.bars) { b in
                    let h = max(1.5, plotH * b.minutes / top)
                    Rectangle()
                        .fill(b.flare ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.16))
                        .overlay { if b.flare { Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75) } }
                        .frame(width: barW, height: grown ? h : 1.5)
                        .offset(x: x(b.id), y: markerH + plotH - (grown ? h : 1.5))
                        .animation(animated ? .spring(response: 0.55, dampingFraction: 0.72).delay(0.35 + Double(b.id) * 0.03) : nil, value: grown)
                    if let m = b.marker {
                        Text(m)
                            .font(.system(size: 7))
                            .frame(width: 13, height: 13)
                            .background(b.markerTint == .pink ? Twin.Palette.pink : Twin.Palette.orange)
                            .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 0.75))
                            .offset(x: x(b.id) + barW / 2 - 6.5, y: max(0, markerH + plotH - h - 15))
                    }
                    Text(b.day.formatted(.dateTime.day()))
                        .font(Twin.Typeface.mono(6))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .frame(width: barW + gap, alignment: .center)
                        .offset(x: x(b.id) - gap / 2, y: markerH + plotH + 3)
                }
                // Usual line.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: usualY))
                    p.addLine(to: CGPoint(x: g.size.width, y: usualY))
                }
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 0.75, dash: [3, 2.5]))
                Text("usual \(ReportPage.minutes(facts.usual)) min")
                    .font(Twin.Typeface.mono(6.5))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .padding(.horizontal, 2)
                    .background(Color.white.opacity(0.85))
                    .offset(x: 0, y: usualY - 11)
            }
        }
    }
}
