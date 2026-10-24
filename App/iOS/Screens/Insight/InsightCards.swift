import SwiftUI
import EczemaKit

// MARK: - Thinking → summary

/// One card that morphs: a grey "thinking" pill with the pixel spinner and changing status lines,
/// then a white card where Claude's summary types out with a block caret. The two states swap in order
/// (the old one leaves before the new one comes) and the card clips while it resizes.
struct CaseSummaryCard: View {
    var caseFile: CaseFile
    @ObservedObject var session: InsightSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var bundledAllowed: Bool
    /// A tap on the card: skip the reveal, or stop waiting for a live call.
    var onTap: () -> Void

    private var thinking: Bool { session.phase <= .thinking }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if thinking {
                ThinkingPill(session: session, bundledAllowed: bundledAllowed, stop: onTap)
                    .transition(.swapInPlace(reduceMotion))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(text: "What Claude thinks")
                        Spacer(minLength: 8)
                        SourceTag(caseFile: caseFile)
                    }
                    TypewriterText(text: caseFile.summary, visibleWords: session.typedWords,
                                   caret: session.phase == .typing ? .solid : session.phase == .cards ? .blinking : .hidden)
                }
                .transition(.swapInPlace(reduceMotion))
            }
        }
        .padding(thinking ? 14 : Twin.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(thinking ? Twin.Palette.fill : Twin.Palette.paper, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Twin.Palette.hairline.opacity(thinking ? 0 : 1), lineWidth: Twin.Stroke.hairline))
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .animation(Twin.Motion.spring, value: thinking)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(thinking ? session.statusLine : "What Claude thinks. \(caseFile.summary)")
        .accessibilityHint(session.isAsking ? "Double tap to stop waiting" : "")
    }
}

/// The grey "thinking" content: pixel spinner and the changing status line. When a live call runs long,
/// a second line offers a way out (the bundled analysis in the demo story, else just stop waiting).
struct ThinkingPill: View {
    @ObservedObject var session: InsightSession
    var bundledAllowed: Bool
    var stop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                PixelSpinner()
                ZStack(alignment: .leading) {
                    Text(session.statusLine)
                        .font(Twin.Typeface.sans(15))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(session.statusLine)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .push(from: .bottom), removal: .push(from: .bottom)))
                }
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
                .clipped()
            }
            if session.isAsking && session.isSlow {
                Button(action: stop) {
                    HStack(spacing: 5) {
                        Text("Taking a while.")
                            .font(Twin.Typeface.sans(13))
                            .foregroundStyle(Twin.Palette.inkMuted)
                        Text(bundledAllowed ? "Use the bundled analysis" : "Stop waiting")
                            .font(Twin.Typeface.sans(13, .bold))
                            .underline(color: Twin.Palette.inkFaint)
                            .foregroundStyle(Twin.Palette.ink)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Twin.Palette.ink)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.vertical, 6)
                    .padding(.leading, 31)          // under the status line (spinner 19 + spacing 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -4)))
            }
        }
        .animation(Twin.Motion.spring, value: session.isSlow)
    }
}

/// "Analyze what I have" before anything is on file: the thinking pill on its own.
struct ThinkingCard: View {
    @ObservedObject var session: InsightSession
    var bundledAllowed: Bool
    var stop: () -> Void

    var body: some View {
        ThinkingPill(session: session, bundledAllowed: bundledAllowed, stop: stop)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Twin.Palette.fill, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
            .onTapGesture(perform: stop)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(session.statusLine)
            .accessibilityHint("Double tap to stop waiting")
    }
}

/// "Live" (lime dot) or "Bundled" in small mono print, read from the case file on screen.
struct SourceTag: View {
    var caseFile: CaseFile
    var body: some View {
        let live = !caseFile.isBundled
        HStack(spacing: 5) {
            if live {
                Rectangle().fill(Twin.Palette.lime).frame(width: 7, height: 7)
                    .overlay(Rectangle().strokeBorder(Twin.Palette.ink, lineWidth: 1))
            }
            Text(live ? "LIVE" : "BUNDLED")
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

            if let window, window.minutes.count >= 2, window.minutes.count == window.days.count,
               let started = suspect.startedOn, let flare = suspect.flareOn, flare > started {
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
                            .fill(hot ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.17))
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

                // The arc from "started" to "flare", its arrowhead riding the tip of the stroke.
                EvidenceArc(from: startTop, control: control, to: CGPoint(x: flareTop.x, y: flareTop.y - 1),
                            progress: drawn)
                    .frame(width: geo.size.width, height: geo.size.height)

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
                    .font(.system(size: 17))
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
                Text(lastLabel)
                    .font(Twin.Typeface.mono(9))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .fixedSize()
                    .position(x: width - 20, y: axisY + 11)
            }
            Text(started)
                .font(Twin.Typeface.mono(9, bold: true))
                .foregroundStyle(Twin.Palette.pinkStrong)
                .fixedSize()
                .position(x: startCenter, y: axisY + 11)
                .opacity(startIn ? 1 : 0)
        }
    }

    private var lastLabel: String {
        guard let last = window.days.last else { return "" }
        if Calendar.current.isDateInToday(last) { return "TODAY" }
        return last.formatted(.dateTime.month(.abbreviated).day()).uppercased()
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
        // The flare tile pops as the arrow comes down to it, so the arrow lands on the tile (never on
        // empty space), and "+2 DAYS" comes with it.
        withAnimation(Twin.Motion.bouncy.delay(1.3)) { flareIn = true }
    }
}

/// The arc from the suspect's start to the flare, drawn up to `progress` (0…1, by length). The arrowhead
/// rides the tip of the stroke and fades in over the first few points, so it is never seen ahead of the line.
private struct EvidenceArc: View, Animatable {
    var from: CGPoint
    var control: CGPoint
    var to: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            let points = (0...40).map { i -> CGPoint in
                let t = CGFloat(i) / 40, u = 1 - t
                return CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                               y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
            }
            var lengths: [CGFloat] = [0]
            for i in 1..<points.count { lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
            guard let total = lengths.last, total > 0, progress > 0.001 else { return }
            let target = total * min(max(progress, 0), 1)

            // The point `length` along the curve, and the direction there.
            func locate(_ length: CGFloat) -> (CGPoint, CGVector, Int) {
                for i in 1..<points.count where lengths[i] >= length {
                    let seg = lengths[i] - lengths[i - 1]
                    let t = seg > 0 ? (length - lengths[i - 1]) / seg : 0
                    let a = points[i - 1], b = points[i]
                    return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), CGVector(dx: b.x - a.x, dy: b.y - a.y), i)
                }
                let n = points.count - 1
                return (points[n], CGVector(dx: points[n].x - points[n - 1].x, dy: points[n].y - points[n - 1].y), n)
            }

            let head: CGFloat = 7, half: CGFloat = 4
            let (tip, dir, _) = locate(target)
            // The line stops under the head, so its round cap never pokes out of the point.
            let (lineEnd, _, lineIndex) = locate(max(0, target - head * 0.6))
            var line = Path()
            line.move(to: points[0])
            for i in 1..<lineIndex { line.addLine(to: points[i]) }
            line.addLine(to: lineEnd)
            ctx.stroke(line, with: .color(Twin.Palette.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            let len = max(hypot(dir.dx, dir.dy), 0.0001)
            let ux = dir.dx / len, uy = dir.dy / len
            let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            arrow.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            arrow.closeSubpath()
            var headCtx = ctx
            headCtx.opacity = Double(min(1, target / (head * 1.6)))
            headCtx.fill(arrow, with: .color(Twin.Palette.ink))
        }
        .allowsHitTesting(false)
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

/// "Share with my doctor", "Re-run analysis" and the small print about where the analysis came from.
struct InsightActions: View {
    /// e.g. "Bundled analysis · offline", "Live analysis · claude-sonnet-5.5".
    var note: String
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

            VStack(spacing: 4) {
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
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(asking)

                Text(note.uppercased())
                    .font(Twin.Typeface.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(Twin.Motion.spring, value: note)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }
}

/// What the watch has tracked so far, for the no-case-file card (only real numbers from the dataset).
struct TrackedSoFar: Equatable {
    var days: Int
    /// "Your usual" minutes per day, once there are a few days to go on.
    var usual: Double?
    /// Start of a flare that is still going on (nil = none now).
    var flareSince: Date?

    init(dataset: TwinDataset) {
        let tracked = dataset.days.filter { $0.scratchMinutes > 0 || $0.episodeCount > 0 }
        days = tracked.count
        guard tracked.count >= 3, dataset.baselineMinutesPerDay > 0 else { usual = nil; flareSince = nil; return }
        usual = dataset.baselineMinutesPerDay
        let minutes = tracked.map(\.scratchMinutes)
        let runs = StatsEngine.flareRuns(minutes, threshold: StatsEngine.threshold(baseline: dataset.baselineMinutesPerDay))
        if let last = runs.last, last.upperBound >= minutes.count - 2 { flareSince = tracked[last.lowerBound].day } else { flareSince = nil }
    }
}

/// Nothing on file yet (your own data, or Douglas's story before day 14). Says honestly what would help:
/// keep tracking, add a key, or try again. Never shows someone else's analysis.
struct NoCaseFileCard: View {
    enum State: Equatable { case ready, needsKey, badKey, noCredits, offline, slow, failed }

    var state: State
    var stats: TrackedSoFar
    var isDemo: Bool
    var run: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 40, height: 40)
                .sticker(state == .ready || state == .needsKey ? Twin.Palette.pink : Twin.Palette.orange)
                .animation(Twin.Motion.bouncy, value: state)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(Twin.Typeface.title)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Text(message)
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            if stats.days > 0 {
                trackedRow
                    .padding(.top, 2)
            }

            Button(action: state == .needsKey || state == .badKey ? openSettings : run) {
                HStack(spacing: 8) {
                    if state == .needsKey || state == .badKey {
                        Image(systemName: "key.fill").font(.system(size: 13, weight: .bold))
                    } else if state != .ready {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                    }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink))
            .padding(.top, 2)
        }
        .twinCard()
        .animation(Twin.Motion.spring, value: state)
        .accessibilityElement(children: .contain)
    }

    private var trackedRow: some View {
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let daysText = stats.days == 1 ? "1 day tracked" : "\(stats.days) days tracked"
        let stickers = Group {
            Sticker(text: daysText, icon: "applewatch", fill: Twin.Palette.paper)
            if let usual = stats.usual {
                Sticker(text: "Usual \(Int(usual.rounded())) min", fill: Twin.Palette.paper)
                if let since = stats.flareSince {
                    Sticker(text: "Flare since \(since.formatted(f))", icon: "flame.fill", fill: Twin.Palette.orange)
                } else {
                    Sticker(text: "No flare now", icon: "checkmark", fill: Twin.Palette.lime)
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { stickers }
            VStack(alignment: .leading, spacing: 6) { stickers }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch state {
        case .ready: "sparkle"
        case .needsKey: "key.fill"
        case .badKey: "key.fill"
        case .noCredits: "creditcard"
        case .offline: "wifi.slash"
        case .slow: "hourglass"
        case .failed: "exclamationmark.bubble"
        }
    }

    private var title: String {
        switch state {
        case .ready: "No case file yet"
        case .needsKey: "Claude needs your key"
        case .badKey: "Your key didn’t work"
        case .noCredits: "Out of OpenRouter credits"
        case .offline: "You’re offline"
        case .slow: "Claude is slow right now"
        case .failed: "Claude didn’t answer"
        }
    }

    private var message: String {
        switch state {
        case .ready:
            if stats.usual == nil {
                return "Claude looks for triggers once your watch has a few days of scratching to compare. Keep wearing it, and tag anything new with the pink + button."
            }
            if stats.flareSince != nil {
                return "There’s enough to compare now. Claude can look at what changed in the 1–3 days before your scratching rose."
            }
            return "No flare so far, so there’s no trigger to find yet. Keep wearing your watch, and tag anything new with the pink + button."
        case .needsKey:
            return isDemo
                ? "Add an OpenRouter key in Settings to analyze these days live. The bundled case file only covers day 14 of Douglas’s story."
                : "Add your OpenRouter key in Settings to analyze your own data. It stays in this phone’s Keychain."
        case .badKey:
            return "OpenRouter didn’t accept the key saved in Settings. Check it there, then analyze again."
        case .noCredits:
            return "Your OpenRouter account has no credits left. Add some on openrouter.ai, then try again."
        case .offline:
            return "Claude can’t be reached right now. Your data stays on this phone; try again once you’re back online."
        case .slow:
            return "No answer within \(Int(InsightSession.liveLimit)) seconds, so the request was stopped. Try again in a minute."
        case .failed:
            return "The model sent nothing usable this time. Try again in a minute, or pick another model in Settings."
        }
    }

    private var buttonTitle: String {
        switch state {
        case .ready: "Analyze what I have"
        case .needsKey, .badKey: "Open Settings"
        case .noCredits, .offline, .slow, .failed: "Try again"
        }
    }
}
