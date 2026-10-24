import SwiftUI
import EczemaKit

/// Test — the 10-day experiment Claude suggested. Empty state (start it), running state (progress ring,
/// day tiles, before/after bars) and the day-10 result moment (the card flips to "Confirmed" with a burst).
struct ExperimentScreen: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var session = ExperimentSession.shared

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
        // The result burst flies over the whole page (top bar included, not clipped by the scroll view) and
        // comes from behind the result card, which stays in front of it.
        .overlayPreferenceValue(ResultCardAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    CelebrationBurst(trigger: session.burst, card: proxy[anchor])
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func subtitle(_ p: ExperimentProgress?) -> String {
        if let p { return p.experiment.plan.title }
        return app.dataset.caseFile?.nextExperiment != nil ? "Suggested by Claude" : "No test running"
    }

    @ViewBuilder
    private func trailing(_ p: ExperimentProgress?) -> some View {
        if let p {
            // The verdict waits for the result moment: until the card turns, the last day still reads "Day 10 / 10".
            switch p.isFinished && !session.resultShown ? .running : p.status {
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
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        } else {
            UserAvatar()
        }
    }
}

/// `-autoAdvance 1` (launch argument, Debug builds): fast-forward a day every 1.8 s until day 10, to record
/// the progression and the result moment without touching the screen. No effect otherwise.
@MainActor
enum AutoAdvance {
    private static var started = false
    static func startIfAsked(app: AppState) {
        #if DEBUG
        let asked = UserDefaults.standard.integer(forKey: "autoAdvance") > 0
        #else
        let asked = false
        #endif
        guard !started, asked else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            while let p = ExperimentProgress(dataset: app.dataset), !p.isFinished {
                StoryTravel.setExperimentDay(p.day + 1, app: app)
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
            #if DEBUG
            // `-experimentQA runAgain`: after the result moment, tap "Run it again" once.
            if UserDefaults.standard.string(forKey: "experimentQA") == "runAgain" {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                StoryTravel.setExperimentDay(1, app: app)
            }
            #endif
        }
    }
}

/// The result moment for this launch: whether the current result was already celebrated, and the burst
/// (drawn by `ExperimentScreen` over the whole page).
@MainActor
final class ExperimentSession: ObservableObject {
    static let shared = ExperimentSession()
    var celebrated = false
    /// The result face is showing (the top bar's verdict sticker waits for it).
    @Published var resultShown = false
    /// Bumps once per burst.
    @Published var burst = 0
    /// Bumps whenever a celebration starts or is called off, so steps still pending can tell they're stale.
    var generation = 0
}

/// The result card's frame, for the burst that comes from behind it.
struct ResultCardAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

// MARK: - Running / finished

struct RunningExperimentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: ExperimentProgress

    /// Scroll target 16 pt above the hero card.
    static let heroID = "experiment-hero"

    /// 0 = progress face, 180 = result face.
    @State private var angle: Double = ExperimentSession.shared.celebrated ? 180 : 0
    @State private var pop = false
    @State private var ringPulse = 0
    /// The first entrance is over: views that arrive later (a new bar, the "What now" card) use their own
    /// motion only.
    @State private var settled = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                FlipCard(angle: angle, reduceMotion: reduceMotion) {
                    ProgressFace(progress: progress, reduceMotion: reduceMotion, ringPulse: ringPulse)
                } back: {
                    if progress.isFinished { ResultFace(progress: progress) }
                }
                .anchorPreference(key: ResultCardAnchor.self, value: .bounds) { $0 }
                .scaleEffect(pop ? 1.035 : 1)
                // A real layout frame 16 pt above the card (an offset would not move it), so scrolling to it
                // keeps the screen's top margin.
                .background(alignment: .top) {
                    Color.clear.frame(width: 1, height: Twin.Space.l + 1).id(Self.heroID).padding(.top, -Twin.Space.l)
                }
                .entranceRise(0.04)

                // Demo time travel only makes sense in the demo story: in real mode (Settings → Demo story
                // off) a fast-forward would swap the user's own data for the demo.
                if app.dataset.isDemo {
                    DemoChip(progress: progress)
                        .frame(maxWidth: .infinity)
                        .entranceRise(0.04 + Twin.Motion.stagger)
                }

                ComparisonCard(progress: progress, settled: settled)
                    .entranceRise(0.04 + 2 * Twin.Motion.stagger)

                if progress.isFinished {
                    WhatNowCard(progress: progress)
                        .transition(.swapInPlace(reduceMotion))
                        .entranceRise(0.04 + 3 * Twin.Motion.stagger, enabled: !settled)
                } else {
                    TipCard(progress: progress)
                        .transition(.swapInPlace(reduceMotion))
                        .entranceRise(0.04 + 3 * Twin.Motion.stagger, enabled: !settled)
                }
                Color.clear.frame(height: 1).id(ScrollHook.bottomID)
            }
            .onAppear {
                ScrollHook.scrollIfAsked(proxy, after: 3.2)
                AutoAdvance.startIfAsked(app: app)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { settled = true }
                if progress.isFinished && !ExperimentSession.shared.celebrated {
                    // The ring fills from 0 on appear and closes at about 1 s.
                    celebrate(ringClosesIn: 1.0, scroll: nil)
                } else if !progress.isFinished {
                    ExperimentSession.shared.celebrated = false
                    ExperimentSession.shared.resultShown = false
                    angle = 0
                }
            }
            .onChange(of: progress.isFinished) { _, finished in
                if finished {
                    // Day 9 → 10: the ring visibly closes about 0.7 s after the day arrives.
                    celebrate(ringClosesIn: 0.7, scroll: proxy)
                } else {
                    let session = ExperimentSession.shared
                    session.celebrated = false
                    session.generation += 1          // calls off any step still pending
                    withAnimation(Twin.Motion.spring) { session.resultShown = false }
                    pop = false
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : Twin.Motion.spring) { angle = 0 }
                }
            }
        }
    }

    /// The result moment, in order: back to the top; the ring closes at day 10 (a soft tick and a small
    /// pulse); a short beat; then the card turns over to the result with a burst and a success haptic.
    /// With Reduce Motion the faces cross-fade and nothing flies.
    private func celebrate(ringClosesIn delay: Double, scroll proxy: ScrollViewProxy?) {
        let session = ExperimentSession.shared
        session.celebrated = true
        session.generation += 1
        let generation = session.generation
        let confirmed = progress.status == .confirmed
        if let proxy { withAnimation(Twin.Motion.spring) { proxy.scrollTo(Self.heroID, anchor: .top) } }

        func later(_ seconds: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                guard session.generation == generation else { return }
                step()
            }
        }

        if reduceMotion {
            later(delay + 0.15) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    angle = 180
                    session.resultShown = true
                }
                confirmed ? Haptics.success() : Haptics.warning()
            }
            return
        }
        later(delay) {
            ringPulse += 1
            Haptics.soft()
        }
        let flip = delay + 0.5
        later(flip) { withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) { angle = 180 } }
        // About when the card is edge-on and the result face takes over.
        later(flip + 0.28) {
            if confirmed { session.burst += 1 }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pop = true }
            withAnimation(Twin.Motion.bouncy) { session.resultShown = true }
            confirmed ? Haptics.success() : Haptics.warning()
        }
        later(flip + 0.44) { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = false } }
    }
}

// MARK: - Flip

/// A card with two faces that flips around the vertical axis. The faces swap at 90°.
/// With Reduce Motion it doesn't turn: the faces cross-fade in place (animate `angle` with a short ease).
struct FlipCard<Front: View, Back: View>: View {
    var angle: Double
    var reduceMotion = false
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back

    var body: some View {
        if reduceMotion {
            let showingBack = angle > 90
            ZStack(alignment: .top) {
                front().opacity(showingBack ? 0 : 1).accessibilityHidden(showingBack)
                back().opacity(showingBack ? 1 : 0).accessibilityHidden(!showingBack)
            }
        } else {
            ZStack(alignment: .top) {
                front().modifier(FaceVisibility(angle: angle, isBack: false))
                back()
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .modifier(FaceVisibility(angle: angle, isBack: true))
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
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
    /// Bumps when the ring closes on the last day.
    var ringPulse = 0

    var body: some View {
        VStack(spacing: 16) {
            DayRing(day: progress.day, length: progress.length, pulse: ringPulse)
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
    /// Bumps to give the ring a small pulse (the last day closing it).
    var pulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        DayRingFrame(value: shown, length: length)
            .keyframeAnimator(initialValue: 1.0, trigger: pulse) { view, scale in
                view.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                CubicKeyframe(1.06, duration: 0.14)
                SpringKeyframe(1, duration: 0.5, spring: .bouncy)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: ExperimentProgress
    /// The screen's entrance is over (numbers that change later start at once).
    var settled = false

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
                           beforeLabel: withLabel, duringLabel: pausedLabel, settled: settled)

            HStack(alignment: .center, spacing: 10) {
                ChangeSticker(percentLess: progress.percentLess, final: progress.isFinished, delay: settled ? 0.15 : 0.5)
                Spacer(minLength: 4)
                // "8 → 7 more days" rolls its digit; a different kind of caption swaps in order instead.
                ZStack(alignment: .trailing) {
                    Text(caption)
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.numericText())
                        .id(captionKind)
                        .transition(.swapInPlace(reduceMotion))
                }
            }
        }
        .twinCard()
    }

    private var captionKind: Int { progress.isFinished ? 2 : progress.during == nil ? 0 : 1 }

    private var caption: String {
        if progress.isFinished { return "Test complete" }
        if progress.during == nil { return "First full day counts tomorrow" }
        let left = progress.daysLeft
        return left == 1 ? "1 more day to be sure" : "\(left) more days to be sure"
    }
}

/// Two big bars (before = orange, during = lime) with counted numbers and a dashed "usual" line.
/// Each bar grows from zero when it first appears, also the "during" bar that arrives on day 2.
struct ComparisonBars: View {
    var before: Double
    var during: Double?
    var usual: Double
    var beforeLabel: String
    var duringLabel: String
    /// The screen's entrance is over: a bar that arrives later grows at once, not after the entrance delay.
    var settled = false

    @State private var lineIn = false
    private let barArea: CGFloat = 112

    var body: some View {
        let top = max(before, during ?? 0, usual, 1)
        let h: (Double) -> CGFloat = { v in max(4, CGFloat(v / top) * barArea) }
        HStack(alignment: .bottom, spacing: 14) {
            BarColumn(value: before, height: h(before), color: Twin.Palette.orange, label: beforeLabel,
                      delay: 0.2, barArea: barArea)
            BarColumn(value: during, height: during.map(h) ?? 0, color: Twin.Palette.lime, label: duringLabel,
                      delay: settled ? 0.05 : 0.45, barArea: barArea)
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
            .opacity(lineIn ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.9)) { lineIn = true } }
    }
}

private struct BarColumn: View {
    var value: Double?
    var height: CGFloat
    var color: Color
    var label: String
    var delay: Double
    var barArea: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let value {
                    CountUp(value: value, font: Twin.Typeface.sans(24, .bold), delay: delay, duration: 1.0)
                        .transition(.opacity)
                } else {
                    Text("—").font(Twin.Typeface.sans(24, .bold)).foregroundStyle(Twin.Palette.inkHint)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
            }
            .frame(height: 30)
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: barArea)
                if value != nil {
                    GrowingBar(height: height, color: color, delay: delay)
                } else {
                    RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                        .strokeBorder(Twin.Palette.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: 92, height: 30)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
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

/// One bar that grows from zero with a spring when it appears, then follows its value.
private struct GrowingBar: View {
    var height: CGFloat
    var color: Color
    var delay: Double
    @State private var grown = false

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Twin.Radius.chip, topTrailingRadius: Twin.Radius.chip, style: .continuous)
        shape.fill(color)
            .overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .frame(width: 92, height: grown ? height : 0)
            .animation(Twin.Motion.spring, value: height)
            .transition(.identity)
            .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(delay)) { grown = true } }
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

/// "▼ 30% less so far" (lime) / "▲ 5% more so far" (orange) / "Day 1 · just started" (paper).
/// The number sticker stamps in when its count starts (never a "0%" with its final arrow and words), and
/// a turn from "more" to "less" stamps a fresh one.
struct ChangeSticker: View {
    var percentLess: Int?
    var final = false
    /// When the count starts (and the sticker stamps in).
    var delay: Double = 0.5

    var body: some View {
        ZStack(alignment: .leading) {
            if let p = percentLess {
                ChangeValueSticker(percentLess: p, final: final, delay: delay)
                    .id(p >= 0)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else {
                Sticker(text: "Day 1 · just started", icon: "clock", fill: Twin.Palette.paper)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .fixedSize()
    }
}

private struct ChangeValueSticker: View {
    var percentLess: Int
    var final: Bool
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    @State private var shown: Double = 0

    var body: some View {
        let less = percentLess >= 0
        HStack(spacing: 5) {
            Image(systemName: less ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .font(.system(size: 9, weight: .bold))
            HStack(spacing: 0) {
                CountingText(value: shown, font: Twin.Typeface.sans(13, .bold))
                Text((less ? "% less" : "% more") + (final ? "" : " so far")).font(Twin.Typeface.sans(13, .bold))
            }
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .sticker(less ? Twin.Palette.lime : Twin.Palette.orange)
        .scaleEffect(stamped || reduceMotion ? 1 : 0.55, anchor: .leading)
        .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -9), anchor: .leading)
        .opacity(stamped ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : Twin.Motion.bouncy.delay(delay)) { stamped = true }
            withAnimation(.easeOut(duration: 0.9).delay(delay)) { shown = Double(abs(percentLess)) }
        }
        .onChange(of: percentLess) { _, new in withAnimation(.easeOut(duration: 0.9)) { shown = Double(abs(new)) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(abs(percentLess))% \(less ? "less" : "more")\(final ? "" : " so far")")
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

/// Demo time travel, clearly not part of the product (dashed): "Fast-forward a day" while the test runs,
/// "Run it again from day 1" once it is done. It sits right under the ring so the audience watches the ring
/// tick up while the presenter taps, and the demo tour shows its touch here.
struct DemoChip: View {
    @EnvironmentObject var app: AppState
    var progress: ExperimentProgress

    var body: some View {
        let done = progress.isFinished
        Button {
            StoryTravel.setExperimentDay(done ? 1 : progress.day + 1, app: app)
        } label: {
            HStack(spacing: 8) {
                Text("DEMO")
                    .font(Twin.Typeface.mono(10, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Twin.Palette.inkHint)
                Rectangle().fill(Twin.Palette.hairline).frame(width: 1, height: 14)
                Text(done ? "Run it again from day 1" : "Fast-forward a day")
                    .font(Twin.Typeface.sans(13, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .contentTransition(.opacity)
                Image(systemName: done ? "arrow.counterclockwise" : "forward.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .tourTarget("fastForward")
        .animation(Twin.Motion.spring, value: done)
        .accessibilityLabel(done ? "Demo: run the test again from day 1" : "Demo: fast-forward a day")
    }
}
