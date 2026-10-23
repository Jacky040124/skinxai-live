import SwiftUI
import EczemaKit

// MARK: - Thinking → summary

/// One card that morphs: a grey "thinking" pill with the pixel spinner and changing status lines,
/// then a white card where Claude's summary types out with a block caret.
struct CaseSummaryCard: View {
    var caseFile: CaseFile
    @ObservedObject var session: InsightSession

    private var thinking: Bool { session.phase <= .thinking }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if thinking {
                HStack(spacing: 12) {
                    PixelSpinner()
                    ZStack(alignment: .leading) {
                        Text(session.statusLine)
                            .font(Twin.Typeface.sans(15))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(session.statusLine)
                            .transition(.asymmetric(insertion: .push(from: .bottom), removal: .push(from: .bottom)))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
                    .clipped()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(text: "What Claude thinks")
                        Spacer(minLength: 8)
                        SourceTag(source: session.source)
                    }
                    TypewriterText(text: caseFile.summary, visibleWords: session.typedWords,
                                   caret: session.phase == .typing ? .solid : session.phase == .cards ? .blinking : .hidden)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .padding(thinking ? 14 : Twin.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(thinking ? Twin.Palette.fill : Twin.Palette.paper,
                    in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline.opacity(thinking ? 0 : 1), lineWidth: Twin.Stroke.hairline))
        .animation(Twin.Motion.spring, value: thinking)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(thinking ? session.statusLine : "What Claude thinks. \(caseFile.summary)")
    }
}

/// "Live" (lime dot) or "Bundled" in small mono print.
struct SourceTag: View {
    var source: InsightSession.Source
    var body: some View {
        HStack(spacing: 5) {
            if source.isLive {
                Rectangle().fill(Twin.Palette.lime).frame(width: 7, height: 7)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
            }
            Text(source.isLive ? "LIVE" : "BUNDLED")
                .font(Twin.Typeface.mono(10))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
        }
    }
}

// MARK: - Typewriter

enum CaretState { case solid, blinking, hidden }

/// Text that appears word by word with a block caret. The final layout is reserved from the start,
/// so nothing below jumps while it types.
struct TypewriterText: View {
    var text: String
    var visibleWords: Int
    var caret: CaretState
    var font: Font = Twin.Typeface.sans(17)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text + " ▍").font(font).lineSpacing(5).hidden()
            // One stable view for every caret state (a view swap would cross-fade the text).
            TimelineView(.animation(minimumInterval: 0.4, paused: caret != .blinking)) { ctx in
                composed(caretOn: caretOn(at: ctx.date))
            }
            .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caretOn(at date: Date) -> Bool {
        switch caret {
        case .solid: true
        case .hidden: false
        case .blinking: Int(date.timeIntervalSinceReferenceDate / 0.4) % 2 == 0
        }
    }

    /// Typed words in ink, the caret, then the rest in clear ink so line breaks never move.
    private func composed(caretOn: Bool) -> some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        let n = min(visibleWords, words.count)
        let shown = words.prefix(n).joined(separator: " ")
        let rest = words.dropFirst(n).joined(separator: " ")
        var line = Text(shown).foregroundColor(Twin.Palette.ink)
            + Text(n > 0 ? " ▍" : "▍").foregroundColor(caretOn ? Twin.Palette.ink : .clear)
        if !rest.isEmpty { line = line + Text(" " + rest).foregroundColor(.clear) }
        return line.font(font).lineSpacing(5)
    }
}

// MARK: - Suspect card

struct SuspectCard: View {
    var rank: Int
    var suspect: Suspect
    /// The days to draw the evidence timeline over (#1 only).
    var window: EvidenceWindow?
    var instant: Bool

    @State private var fill: Double = 0
    private var top: Bool { rank == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(Twin.Typeface.mono(12, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 26, height: 26)
                    .sticker(Twin.Palette.paper)
                Text(suspect.title)
                    .font(Twin.Typeface.sans(18, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
                Spacer(minLength: 6)
                Sticker(text: suspect.confidence.label, fill: top ? Twin.Palette.yellow : Twin.Palette.paper)
                    .padding(.top, 1)
            }

            ConfidenceBar(value: fill)
                .padding(.top, 2)
                .accessibilityLabel("Confidence \(suspect.confidence.label)")

            Text(evidence)
                .font(Twin.Typeface.sans(14))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let window, let started = suspect.startedOn, let flare = suspect.flareOn, flare > started {
                EvidenceTimeline(window: window, startedOn: started, flareOn: flare,
                                 emoji: suspect.kind?.emoji ?? "✳️", instant: instant)
                    .padding(.top, 4)
            } else if let meta {
                Text(meta)
                    .font(Twin.Typeface.mono(10))
                    .tracking(0.5)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(top ? Twin.Palette.yellowSoft : Twin.Palette.paper,
                    in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        .accessibilityElement(children: .combine)
        .onAppear {
            if instant { fill = suspect.confidence.score; return }
            withAnimation(Twin.Motion.fill.delay(0.18)) { fill = suspect.confidence.score }
        }
    }

    /// The evidence sentence with the lag in bold ink.
    private var evidence: AttributedString {
        var s = AttributedString(suspect.evidence)
        let lag = suspect.lag
        let candidates = [lag, lag.replacingOccurrences(of: "about ", with: ""), lag.replacingOccurrences(of: "–", with: "-")]
        for c in candidates where !c.isEmpty {
            if let r = s.range(of: c) {
                s[r].font = Twin.Typeface.sans(14, .bold)
                s[r].foregroundColor = Twin.Palette.ink
                break
            }
        }
        return s
    }

    private var meta: String? {
        var parts: [String] = []
        if let d = suspect.startedOn { parts.append("Started \(d.formatted(.dateTime.month(.abbreviated).day()))") }
        if !suspect.lag.isEmpty { parts.append("lag \(suspect.lag)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ").uppercased()
    }
}

struct ConfidenceBar: View {
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Twin.Palette.ink.opacity(0.08))
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Twin.Palette.cyan)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Evidence timeline

struct EvidenceWindow {
    var days: [Date]
    var minutes: [Double]
    var threshold: Double
}

/// The #1 suspect's story on a strip of days: little bars of daily scratching, a pink tile on the day it
/// started, an orange tile on the day the flare began, and an arc that draws itself between them.
struct EvidenceTimeline: View {
    var window: EvidenceWindow
    var startedOn: Date
    var flareOn: Date
    var emoji: String
    var instant: Bool

    @State private var grown = false
    @State private var startIn = false
    @State private var drawn: CGFloat = 0
    @State private var flareIn = false

    private let height: CGFloat = 124
    private let axisFromBottom: CGFloat = 20
    private let maxBar: CGFloat = 46
    private let tile: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let n = max(window.days.count, 1)
            let col = geo.size.width / CGFloat(n)
            let axisY = geo.size.height - axisFromBottom
            let peak = max(window.minutes.max() ?? 1, 1)
            let si = index(of: startedOn), fi = index(of: flareOn)
            let barH: (Int) -> CGFloat = { i in max(3, CGFloat(window.minutes[i] / peak) * maxBar) }
            let x: (Int) -> CGFloat = { i in col * (CGFloat(i) + 0.5) }
            let startTop = CGPoint(x: x(si), y: axisY - barH(si) - 6 - tile)
            let flareTop = CGPoint(x: x(fi), y: axisY - barH(fi) - 6 - tile)
            let control = CGPoint(x: (startTop.x + flareTop.x) / 2, y: min(startTop.y, flareTop.y) - 34)
            let apex = CGPoint(x: 0.25 * startTop.x + 0.5 * control.x + 0.25 * flareTop.x,
                               y: 0.25 * startTop.y + 0.5 * control.y + 0.25 * flareTop.y)
            let lag = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startedOn),
                                                      to: Calendar.current.startOfDay(for: flareOn)).day ?? 0

            ZStack(alignment: .topLeading) {
                // Daily bars.
                ForEach(0..<window.minutes.count, id: \.self) { i in
                    let hot = window.minutes[i] > window.threshold
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(hot ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Twin.Palette.ink.opacity(hot ? 1 : 0), lineWidth: 1))
                            .frame(height: grown ? barH(i) : 0)
                    }
                    .frame(width: max(col * 0.52, 4), height: maxBar)
                    .position(x: x(i), y: axisY - maxBar / 2)
                    .animation(instant ? nil : .spring(response: 0.5, dampingFraction: 0.72).delay(0.12 + Double(i) * 0.03), value: grown)
                }

                // Axis.
                Rectangle().fill(Twin.Palette.hairline)
                    .frame(width: geo.size.width, height: 1)
                    .position(x: geo.size.width / 2, y: axisY + 0.5)

                // The arc from "started" to "flare".
                Path { p in
                    p.move(to: startTop)
                    p.addQuadCurve(to: flareTop, control: control)
                }
                .trim(from: 0, to: drawn)
                .stroke(Twin.Palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                ArrowHead()
                    .fill(Twin.Palette.ink)
                    .frame(width: 8, height: 7)
                    .rotationEffect(.radians(atan2(flareTop.y - control.y, flareTop.x - control.x) - .pi / 2))
                    .position(x: flareTop.x, y: flareTop.y - 3)
                    .opacity(drawn > 0.96 ? 1 : 0)

                Text(lag == 1 ? "+1 DAY" : "+\(lag) DAYS")
                    .font(Twin.Typeface.mono(10, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Twin.Palette.yellowSoft)
                    .position(x: apex.x, y: apex.y - 11)
                    .opacity(flareIn ? 1 : 0)
                    .offset(y: flareIn ? 0 : 4)

                // Tiles.
                Text(emoji)
                    .font(.system(size: 15))
                    .frame(width: tile, height: tile)
                    .sticker(Twin.Palette.pink)
                    .scaleEffect(startIn ? 1 : 0.2)
                    .opacity(startIn ? 1 : 0)
                    .position(x: startTop.x, y: startTop.y + tile / 2)
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: tile, height: tile)
                    .sticker(Twin.Palette.orange)
                    .scaleEffect(flareIn ? 1 : 0.2)
                    .opacity(flareIn ? 1 : 0)
                    .position(x: flareTop.x, y: flareTop.y + tile / 2)

                // Labels under the axis.
                axisLabels(width: geo.size.width, axisY: axisY, startX: startTop.x)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Started \(startedOn.formatted(.dateTime.month(.wide).day())); the flare began \(flareOn.formatted(.dateTime.month(.wide).day())).")
        .onAppear(perform: play)
    }

    private func axisLabels(width: CGFloat, axisY: CGFloat, startX: CGFloat) -> some View {
        let started = "\(startedOn.formatted(.dateTime.month(.abbreviated).day()).uppercased()) · STARTED"
        let first = window.days.first.map { $0.formatted(.dateTime.month(.abbreviated).day()).uppercased() } ?? ""
        let labelWidth: CGFloat = 104
        let startCenter = min(max(startX, labelWidth / 2), width - labelWidth / 2)
        return ZStack(alignment: .topLeading) {
            if startCenter - labelWidth / 2 > 56 {
                Text(first)
                    .font(Twin.Typeface.mono(9))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
                    .position(x: 22, y: axisY + 11)
            }
            if width - (startCenter + labelWidth / 2) > 44 {
                Text("TODAY")
                    .font(Twin.Typeface.mono(9))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
                    .position(x: width - 16, y: axisY + 11)
            }
            Text(started)
                .font(Twin.Typeface.mono(9, bold: true))
                .foregroundStyle(Twin.Palette.pinkStrong)
                .fixedSize()
                .position(x: startCenter, y: axisY + 11)
                .opacity(startIn ? 1 : 0)
        }
    }

    private func index(of date: Date) -> Int {
        let cal = Calendar.current
        if let i = window.days.firstIndex(where: { cal.isDate($0, inSameDayAs: date) }) { return i }
        return date < (window.days.first ?? date) ? 0 : max(window.days.count - 1, 0)
    }

    private func play() {
        if instant {
            grown = true; startIn = true; drawn = 1; flareIn = true
            return
        }
        grown = true
        withAnimation(Twin.Motion.bouncy.delay(0.55)) { startIn = true }
        withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.9).delay(0.75)) { drawn = 1 }
        withAnimation(Twin.Motion.bouncy.delay(1.5)) { flareIn = true }
    }
}

private struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Notes, red flags, actions

struct CannotSeparateNote: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Twin.Palette.orange).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("CAN'T SEPARATE YET")
                    .font(Twin.Typeface.mono(10, bold: true))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.orangeStrong)
                Text(text)
                    .font(Twin.Typeface.sans(14))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}

struct RedFlagsCard: View {
    var flags: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 30, height: 30)
                    .sticker(Twin.Palette.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("See a doctor today").font(Twin.Typeface.sans(17, .bold)).foregroundStyle(Twin.Palette.ink)
                    Text("Claude spotted warning signs in your log").font(Twin.Typeface.sans(13)).foregroundStyle(Twin.Palette.inkMuted)
                }
            }
            ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Rectangle().fill(Twin.Palette.redStrong).frame(width: 5, height: 5).offset(y: -3)
                    Text(flag).font(Twin.Typeface.sans(14)).foregroundStyle(Twin.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.redSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        .accessibilityElement(children: .combine)
    }
}

/// Pink "Start a 10-day test" (or, once a test runs, a cyan way back to it).
struct StartTestButton: View {
    @EnvironmentObject var app: AppState
    var plan: ExperimentPlan
    var experiment: Experiment?
    var day: Int
    /// Red flags: the doctor comes first, so the test is not the main action.
    var quiet: Bool

    var body: some View {
        if let experiment {
            let done = experiment.status != .running
            Button { app.select(.experiment) } label: {
                HStack(spacing: 8) {
                    Text(done ? "Test finished · see the result" : "Your test · day \(max(day, 1)) of \(experiment.plan.lengthDays)")
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: done ? Twin.Palette.lime : Twin.Palette.cyan))
        } else {
            Button { app.startExperiment() } label: {
                HStack(spacing: 8) {
                    Text("Start a \(plan.lengthDays)-day test: \(lowerFirst(plan.title))")
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(TwinButtonStyle(fill: quiet ? Twin.Palette.paper : Twin.Palette.pink))
        }
    }

    private func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
}

/// "Share with my doctor", "Re-run analysis" and the small print about where the analysis came from.
struct InsightActions: View {
    var source: InsightSession.Source
    var asking: Bool
    var rerun: () -> Void
    var share: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: share) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 14, weight: .bold))
                    Text("Share with my doctor")
                }
                .font(Twin.Typeface.sans(15, .bold))
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 48))

            HStack(spacing: 10) {
                Button(action: rerun) {
                    HStack(spacing: 6) {
                        if asking {
                            PixelSpinner(pixel: 3)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        }
                        Text(asking ? "Asking Claude…" : "Re-run analysis")
                            .font(Twin.Typeface.sans(14, .bold))
                            .underline(!asking, color: Twin.Palette.inkFaint)
                    }
                    .foregroundStyle(Twin.Palette.ink)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(asking)

                Rectangle().fill(Twin.Palette.hairline).frame(width: 1, height: 14)

                Text(source.note.uppercased())
                    .font(Twin.Typeface.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }
}

/// No case file (real data, too little of it yet).
struct NoCaseFileCard: View {
    var asking: Bool
    var run: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 40, height: 40)
                .sticker(Twin.Palette.pink)
            Text("No case file yet").font(Twin.Typeface.title).foregroundStyle(Twin.Palette.ink)
            Text("Claude looks for triggers once your watch has a few days of scratching to compare. Keep wearing it, and tag anything new with the pink + button.")
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: run) {
                HStack(spacing: 8) {
                    if asking { PixelSpinner(pixel: 3) }
                    Text(asking ? "Asking Claude…" : "Analyze what I have")
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink))
            .disabled(asking)
        }
        .twinCard()
    }
}
