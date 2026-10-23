import SwiftUI
import EczemaKit

/// Test — the 10-day experiment Claude suggested. Empty state (start it), running state (progress ring,
/// day tiles, before/after bars) and the day-10 result moment (the card flips to "Confirmed" with a burst).
struct ExperimentScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let progress = ExperimentProgress(dataset: app.dataset)
        ScreenScaffold(title: "Experiment", subtitle: subtitle(progress)) {
            trailing(progress)
        } content: {
            if let progress {
                RunningExperimentView(progress: progress)
            } else {
                SuggestedExperimentView(caseFile: app.dataset.caseFile)
            }
        }
    }

    private func subtitle(_ p: ExperimentProgress?) -> String {
        if let p { return p.experiment.plan.title }
        return app.dataset.caseFile?.nextExperiment != nil ? "Suggested by Claude" : "No test running"
    }

    @ViewBuilder
    private func trailing(_ p: ExperimentProgress?) -> some View {
        if let p {
            switch p.status {
            case .running:
                HStack(spacing: 0) {
                    Text("Day ")
                    Text("\(p.day)").contentTransition(.numericText(value: Double(p.day)))
                    Text(" / \(p.length)")
                }
                .font(Twin.Typeface.sans(13, .bold))
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .sticker(Twin.Palette.cyan)
                .accessibilityLabel("Day \(p.day) of \(p.length)")
            case .confirmed:
                Sticker(text: "Confirmed", icon: "checkmark", fill: Twin.Palette.lime)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .notConfirmed, .stopped:
                Sticker(text: p.status == .stopped ? "Stopped" : "Not confirmed", icon: "xmark", fill: Twin.Palette.orange)
            }
        } else {
            UserAvatar()
        }
    }
}

/// `-autoAdvance 1` (launch argument): fast-forward a day every 1.8 s until day 10, to record the
/// progression and the result moment without touching the screen. No effect otherwise.
@MainActor
enum AutoAdvance {
    private static var started = false
    static func startIfAsked(app: AppState) {
        guard !started, UserDefaults.standard.integer(forKey: "autoAdvance") > 0 else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            while let p = ExperimentProgress(dataset: app.dataset), !p.isFinished {
                app.setExperimentDay(p.day + 1)
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
        }
    }
}

/// Remembers, for this launch, whether the current result was already celebrated.
@MainActor
final class ExperimentSession: ObservableObject {
    static let shared = ExperimentSession()
    var celebrated = false
}

// MARK: - Running / finished

struct RunningExperimentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: ExperimentProgress

    /// 0 = progress face, 180 = result face.
    @State private var angle: Double = ExperimentSession.shared.celebrated ? 180 : 0
    @State private var burst = 0
    @State private var pop = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                FlipCard(angle: angle) {
                    ProgressFace(progress: progress, reduceMotion: reduceMotion)
                } back: {
                    if progress.isFinished { ResultFace(progress: progress) }
                }
                .scaleEffect(pop ? 1.035 : 1)
                // The burst canvas reaches past the card so the stickers can fly out of it.
                .overlay { CelebrationBurst(trigger: burst).padding(-140).allowsHitTesting(false) }
                .background(alignment: .top) { Color.clear.frame(height: 1).offset(y: -Twin.Space.l).id("hero") }
                .riseIn(0.04)

                ComparisonCard(progress: progress)
                    .riseIn(0.04 + Twin.Motion.stagger)

                if progress.isFinished {
                    WhatNowCard(progress: progress)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                        .riseIn(0.04 + 2 * Twin.Motion.stagger)
                } else {
                    TipCard(progress: progress)
                        .transition(.opacity)
                        .riseIn(0.04 + 2 * Twin.Motion.stagger)
                }

                DemoControls(progress: progress)
                    .riseIn(0.04 + 3 * Twin.Motion.stagger)
                Color.clear.frame(height: 1).id(ScrollHook.bottomID)
            }
            .onAppear {
                ScrollHook.scrollIfAsked(proxy, after: 3.2)
                AutoAdvance.startIfAsked(app: app)
                if progress.isFinished && !ExperimentSession.shared.celebrated {
                    celebrate(after: reduceMotion ? 0.2 : 1.5, proxy: nil)
                } else if !progress.isFinished {
                    ExperimentSession.shared.celebrated = false
                    angle = 0
                }
            }
            .onChange(of: progress.isFinished) { _, finished in
                if finished {
                    celebrate(after: 0.35, proxy: proxy)
                } else {
                    ExperimentSession.shared.celebrated = false
                    withAnimation(Twin.Motion.spring) { angle = 0 }
                }
            }
        }
    }

    /// The result moment: back to the top, the card flips, a burst, a success haptic.
    private func celebrate(after delay: Double, proxy: ScrollViewProxy?) {
        ExperimentSession.shared.celebrated = true
        if let proxy { withAnimation(Twin.Motion.spring) { proxy.scrollTo("hero", anchor: .top) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) { angle = 180 }
            } else {
                withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) { angle = 180 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    burst += 1
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pop = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = false }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                progress.status == .confirmed ? Haptics.success() : Haptics.warning()
            }
        }
    }
}

// MARK: - Flip

/// A card with two faces that flips around the vertical axis. The faces swap at 90°.
struct FlipCard<Front: View, Back: View>: View {
    var angle: Double
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back

    var body: some View {
        ZStack(alignment: .top) {
            front().modifier(FaceVisibility(angle: angle, isBack: false))
            back()
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .modifier(FaceVisibility(angle: angle, isBack: true))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

private struct FaceVisibility: ViewModifier, Animatable {
    var angle: Double
    var isBack: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        let showingBack = angle.truncatingRemainder(dividingBy: 360) > 90
        content
            .opacity(showingBack == isBack ? 1 : 0)
            .accessibilityHidden(showingBack != isBack)
    }
}

// MARK: - Faces

/// Front: the cyan progress ring, the 10 day tiles, the dates.
struct ProgressFace: View {
    var progress: ExperimentProgress
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 16) {
            DayRing(day: progress.day, length: progress.length)
            .frame(width: 184, height: 184)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(progress.day) of \(progress.length)")

            DayTiles(day: progress.day, length: progress.length, finished: progress.isFinished, bob: !reduceMotion)

            Text(dates)
                .font(Twin.Typeface.mono(10))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
        }
        .frame(maxWidth: .infinity)
        .twinCard()
    }

    private var dates: String {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: progress.length - 1, to: progress.startDay) ?? progress.startDay
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "STARTED \(progress.startDay.formatted(f).uppercased()) · LAST DAY \(end.formatted(f).uppercased())"
    }
}

/// Back: "Confirmed: the body wash is a trigger for you".
struct ResultFace: View {
    var progress: ExperimentProgress

    private var confirmed: Bool { progress.status == .confirmed }
    private var subject: String { progress.experiment.plan.subject ?? progress.experiment.plan.title.lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: confirmed ? "checkmark" : "xmark").font(.system(size: 11, weight: .heavy))
                    Text(confirmed ? "Confirmed" : "Not confirmed").font(Twin.Typeface.sans(13, .bold))
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .sticker(confirmed ? Twin.Palette.lime : Twin.Palette.orange)
                Spacer()
                Text("DAY \(progress.day) / \(progress.length)")
                    .font(Twin.Typeface.mono(11))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.ink.opacity(0.6))
            }

            Text(confirmed ? "The \(subject) is a trigger for you." : "The \(subject) doesn’t look like the trigger.")
                .font(Twin.Typeface.sans(30, .bold))
                .tracking(-0.8)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(sentence)
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.ink.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            DayTiles(day: progress.day, length: progress.length, finished: true, bob: false)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(confirmed ? Twin.Palette.limeSoft : Twin.Palette.orangeSoft,
                    in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
    }

    private var sentence: String {
        let before = Int(progress.before.rounded())
        let during = Int((progress.during ?? progress.before).rounded())
        let pct = abs(progress.percentLess ?? 0)
        let still = stillThere
        if confirmed {
            return "Scratching fell \(pct)%, from \(before) to \(during) min a day, once you paused it\(still.map { ", \($0)" } ?? "")."
        }
        let change = (progress.percentLess ?? 0) >= 0 ? "fell only \(pct)%" : "rose \(pct)%"
        return "Scratching \(change) (\(before) → \(during) min a day) while you paused it. Claude will look at the next suspect."
    }

    /// "while the air stayed just as dry" — the other suspect that stayed, which makes the result convincing.
    private var stillThere: String? {
        guard let s = progress.stillPresent.first else { return nil }
        switch s.kind {
        case .dryAir:
            let h = progress.humidityDuring.map { " (\(Int($0.rounded()))% humidity)" } ?? ""
            return "while the air stayed just as dry\(h)"
        case .stress: return "even with the stress still there"
        default: return "while \(s.title.lowercased()) stayed the same"
        }
    }
}

// MARK: - Day ring

/// The cyan ring and its day number, driven by one animated value so they always move together.
struct DayRing: View {
    var day: Int
    var length: Int
    @State private var shown: Double = 0

    var body: some View {
        DayRingFrame(value: shown, length: length)
            .onAppear { withAnimation(Twin.Motion.fill.delay(0.15)) { shown = Double(day) } }
            .onChange(of: day) { _, new in withAnimation(Twin.Motion.fill) { shown = Double(new) } }
    }
}

private struct DayRingFrame: View, Animatable {
    var value: Double
    var length: Int
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let lineWidth: CGFloat = 14
        ZStack {
            Circle().stroke(Twin.Palette.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value / Double(max(length, 1)), 0), 1))
                .stroke(Twin.Palette.cyan, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(value.rounded()))")
                    .font(Twin.Typeface.sans(58, .bold))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(Twin.Palette.ink)
                Text("OF \(length) DAYS")
                    .font(Twin.Typeface.mono(11))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Day tiles

/// Ten small stickers: done = lime, today = yellow (bobbing), to come = paper.
struct DayTiles: View {
    var day: Int
    var length: Int
    var finished: Bool
    var bob: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(length, 1), id: \.self) { d in
                let isToday = d == day && !finished
                let done = finished ? d <= day : d < day
                Text("\(d)")
                    .font(Twin.Typeface.mono(d >= 10 ? 9 : 10, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 26, height: 26)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous)
                                .fill(done ? Twin.Palette.lime : Twin.Palette.paper)
                            if isToday {
                                RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous)
                                    .fill(Twin.Palette.yellow)
                                    .matchedGeometryEffect(id: "today", in: ns)
                            }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                    .modifier(Bob(active: isToday && bob))
                    .accessibilityLabel("Day \(d)\(isToday ? ", today" : done ? ", done" : "")")
            }
        }
    }
}

private struct Bob: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([0.0, -3.5]) { view, y in
                view.offset(y: y)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            content
        }
    }
}

// MARK: - Before / after

struct ComparisonCard: View {
    var progress: ExperimentProgress

    private var plan: ExperimentPlan { progress.experiment.plan }
    private var withLabel: String { plan.shortSubject.map { "WITH \($0.uppercased())" } ?? "BEFORE" }
    private var pausedLabel: String { plan.shortSubject != nil ? "PAUSED" : "DURING TEST" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Scratching per day")
                Spacer()
                Text("MIN / DAY")
                    .font(Twin.Typeface.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.inkHint)
            }

            ComparisonBars(before: progress.before, during: progress.during, usual: progress.usual,
                           beforeLabel: withLabel, duringLabel: pausedLabel)

            HStack(alignment: .center, spacing: 10) {
                ChangeSticker(percentLess: progress.percentLess, final: progress.isFinished)
                Spacer(minLength: 4)
                Text(caption)
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.numericText())
            }
        }
        .twinCard()
    }

    private var caption: String {
        if progress.isFinished { return "Test complete" }
        if progress.during == nil { return "First full day counts tomorrow" }
        let left = progress.daysLeft
        return left == 1 ? "1 more day to be sure" : "\(left) more days to be sure"
    }
}

/// Two big bars (before = orange, during = lime) with counted numbers and a dashed "usual" line.
struct ComparisonBars: View {
    var before: Double
    var during: Double?
    var usual: Double
    var beforeLabel: String
    var duringLabel: String

    @State private var grown = false
    private let barArea: CGFloat = 112

    var body: some View {
        let top = max(before, during ?? 0, usual, 1)
        let h: (Double) -> CGFloat = { v in max(4, CGFloat(v / top) * barArea) }
        HStack(alignment: .bottom, spacing: 14) {
            column(value: before, height: h(before), color: Twin.Palette.orange, label: beforeLabel, delay: 0.2)
            column(value: during, height: during.map(h) ?? 0, color: Twin.Palette.lime, label: duringLabel, delay: 0.45)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            // "Your usual" reference line across both bars.
            let y = h(usual)
            ZStack(alignment: .center) {
                Line()
                    .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .frame(height: 1)
                Text("YOUR USUAL · \(Int(usual.rounded()))")
                    .font(Twin.Typeface.mono(9, bold: true))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .padding(.horizontal, 4)
                    .background(Twin.Palette.paper)
                    .offset(y: -9)
            }
            .padding(.bottom, 22 + y)
            .opacity(grown ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.9), value: grown)
        }
        .onAppear { grown = true }
    }

    private func column(value: Double?, height: CGFloat, color: Color, label: String, delay: Double) -> some View {
        VStack(spacing: 6) {
            Group {
                if let value {
                    CountUp(value: value, font: Twin.Typeface.sans(24, .bold), delay: delay, duration: 1.0)
                } else {
                    Text("—").font(Twin.Typeface.sans(24, .bold)).foregroundStyle(Twin.Palette.inkHint)
                }
            }
            .frame(height: 30)
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: barArea)
                if value != nil {
                    UnevenRoundedRectangle(topLeadingRadius: Twin.Radius.chip, topTrailingRadius: Twin.Radius.chip, style: .continuous)
                        .fill(color)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: Twin.Radius.chip, topTrailingRadius: Twin.Radius.chip, style: .continuous)
                            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                        .frame(width: 92, height: grown ? height : 0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(delay), value: grown)
                        .animation(Twin.Motion.spring, value: height)
                } else {
                    RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                        .strokeBorder(Twin.Palette.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: 92, height: 30)
                }
            }
            Text(label)
                .font(Twin.Typeface.mono(10))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// "▼ 30% less so far" (lime) / "▲ 5% more so far" (orange) / "Day 1" (paper).
struct ChangeSticker: View {
    var percentLess: Int?
    var final = false
    var body: some View {
        Group {
            if let p = percentLess {
                HStack(spacing: 5) {
                    Image(systemName: p >= 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                        .font(.system(size: 9, weight: .bold))
                    HStack(spacing: 0) {
                        CountUp(value: Double(abs(p)), font: Twin.Typeface.sans(13, .bold), delay: 0.5, duration: 0.9)
                        Text((p >= 0 ? "% less" : "% more") + (final ? "" : " so far")).font(Twin.Typeface.sans(13, .bold))
                    }
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .sticker(p >= 0 ? Twin.Palette.lime : Twin.Palette.orange)
            } else {
                Sticker(text: "Day 1 · just started", icon: "clock", fill: Twin.Palette.paper)
            }
        }
        .fixedSize()
    }
}

// MARK: - Tip, what now, demo controls

struct TipCard: View {
    var progress: ExperimentProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("Tip: ").bold() + Text(tip))
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let still = progress.stillPresent.first {
                HStack(spacing: 10) {
                    Sticker(text: stillText(still), icon: still.kind?.emoji, fill: Twin.Palette.orange)
                    Text("If scratching keeps falling anyway, it’s the \(progress.experiment.plan.shortSubject ?? "change").")
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .twinCard(fill: Twin.Palette.cream)
    }

    /// "keep food, gym and room humidity the same so the result is clear." from the plan's own words.
    private var tip: String {
        let sentences = progress.experiment.plan.instruction
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
        if let keep = sentences.first(where: { $0.lowercased().hasPrefix("keep") }) {
            return keep.prefix(1).lowercased() + keep.dropFirst() + " so the result is clear."
        }
        return "keep everything else the same so the result is clear."
    }

    private func stillText(_ s: Suspect) -> String {
        if s.kind == .dryAir, let h = progress.humidityDuring { return "Still dry · \(Int(h.rounded()))%" }
        return "Still: \(s.title.lowercased())"
    }
}

struct WhatNowCard: View {
    @EnvironmentObject var app: AppState
    var progress: ExperimentProgress

    var body: some View {
        let confirmed = progress.status == .confirmed
        let subject = progress.experiment.plan.subject ?? "change"
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "What now")
            Text(confirmed
                 ? "Keep the \(subject) out of your routine, and show this test to your doctor at your next visit."
                 : "Go back to normal. Claude will suggest the next test from your suspects.")
                .font(Twin.Typeface.sans(15))
                .foregroundStyle(Twin.Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button { app.showReport = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 14, weight: .bold))
                    Text("Share with my doctor")
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink))
        }
        .twinCard(fill: Twin.Palette.cream)
    }
}

/// Small, clearly secondary controls for the stage demo (dashed frame = not part of the product).
struct DemoControls: View {
    @EnvironmentObject var app: AppState
    var progress: ExperimentProgress

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if progress.isFinished {
                    app.setExperimentDay(nil)
                } else {
                    app.setExperimentDay(progress.day + 1)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(progress.isFinished ? "Run it again" : "Fast-forward a day")
                    Image(systemName: progress.isFinished ? "arrow.counterclockwise" : "forward.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(Twin.Typeface.sans(13, .bold))
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 36, fullWidth: false))

            VStack(alignment: .leading, spacing: 1) {
                Eyebrow(text: "Demo")
                Text(progress.isFinished ? "Replay the test from day 1" : "Jump ahead to the result")
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .padding(.top, 6)
    }
}
