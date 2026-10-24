import SwiftUI

/// The one screen: a big Start / Stop button, tonight's scratch count under it and one line about
/// the big screen.
struct MonitorScreen: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        GeometryReader { geo in
            let m = MonitorMetrics(size: geo.size)
            VStack(spacing: 0) {
                LiveButton(diameter: m.button, reach: m.pulseReach)
                    .padding(.top, m.aboveButton)
                    .watchRise(0.05, distance: 8)
                Spacer(minLength: m.gap)
                ScratchCount(count: model.scratches, scratching: model.scratching, size: m.number)
                    .watchRise(0.14, distance: 8)
                Spacer(minLength: m.gap)
                ScreenStatus()
                    .watchRise(0.2, distance: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Sizes for the watch it runs on (40 mm up to Ultra), measured on the 46 mm (208 × 248 pt).
private struct MonitorMetrics {
    let button: CGFloat
    let aboveButton: CGFloat
    /// How far the pulse ring runs past the button's edge (it has faded out by then, so it may
    /// pass the title row and the gap under the button).
    let pulseReach: CGFloat
    let number: CGFloat
    let gap: CGFloat

    init(size: CGSize) {
        let compact = size.height < 175 || size.width < 180
        number = compact ? 34 : 42
        gap = compact ? 8 : 10
        aboveButton = compact ? 6 : 8
        pulseReach = compact ? 10 : 14
        // Under the button: the count's digits, the status line and the two gaps.
        let below = number * ScratchCount.digitHeight + 17 + 2 * gap
        button = max(72, min(size.width * 0.58, size.height - aboveButton - below))
    }
}

/// Start (pink) / Stop (dark with a cyan ring). While it runs, a ring pulses out of it: cyan, and
/// orange while a scratch is going on.
private struct LiveButton: View {
    @EnvironmentObject var model: WatchModel
    var diameter: CGFloat
    var reach: CGFloat

    var body: some View {
        let on = model.live != .off
        Button { model.toggleLive() } label: {
            ZStack {
                Circle().fill(on ? Twin.Palette.nightCard : Twin.Palette.pink)
                Circle().strokeBorder(Twin.Palette.cyan, lineWidth: 3)
                    .opacity(on ? 1 : 0)
                ButtonFace(live: model.live, diameter: diameter)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(WatchPressStyle(scale: 0.94))
        .background {
            if model.live.isOn {
                PulseRing(color: model.scratching ? Twin.Palette.orange : Twin.Palette.cyan, diameter: diameter, reach: reach)
                    .transition(.opacity)
            }
        }
        .animation(Twin.Motion.spring, value: model.live)
        .animation(Twin.Motion.spring, value: model.scratching)
        .accessibilityLabel(on ? "Stop monitoring" : "Start monitoring")
    }
}

/// "Start", a spinner while it starts, then "Stop" over the time it has been running.
private struct ButtonFace: View {
    var live: WatchModel.LiveState
    var diameter: CGFloat

    var body: some View {
        let label = WatchFont.sans(diameter * 0.22, .bold)
        ZStack {
            switch live {
            case .off:
                Text("Start")
                    .font(label)
                    .foregroundStyle(Twin.Palette.ink)
                    .transition(.blurReplace)
            case .starting:
                PixelSpinner(pixel: 4, color: Twin.Palette.cyan)
                    .transition(.blurReplace)
            case let .on(since, _):
                VStack(spacing: 0) {
                    Text("Stop")
                        .font(label)
                        .foregroundStyle(.white)
                    Text(since, style: .timer)
                        .font(WatchFont.mono(diameter * 0.1))
                        .monospacedDigit()
                        .foregroundStyle(Twin.Palette.cyan)
                }
                .transition(.blurReplace)
            }
        }
        .lineLimit(1)
    }
}

/// A ring that leaves the button's edge like a monitor's ping, thinning and fading as it runs
/// `reach` points out; then a short rest. A still halo instead with Reduce Motion, and in
/// always-on dimming.
private struct PulseRing: View {
    var color: Color
    var diameter: CGFloat
    var reach: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    /// Seconds from one ping to the next, and how long a ring is on its way.
    private let period = 2.0
    private let travel = 1.5

    var body: some View {
        if reduceMotion || dimmed {
            Circle()
                .stroke(color.opacity(0.4), lineWidth: 2)
                .frame(width: diameter + reach, height: diameter + reach)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                let phase = min(1, t / travel)
                let out = 1 - (1 - phase) * (1 - phase)          // ease out: leaves fast, slows down
                let size = diameter + 2 * reach * out
                Circle()
                    .stroke(color, lineWidth: 0.8 + 2.4 * (1 - phase))
                    .frame(width: size, height: size)
                    .opacity(1 - phase)
            }
        }
    }
}

/// Tonight's scratches: a big number that rolls up and bumps on each new one, orange while the
/// scratch goes on.
private struct ScratchCount: View {
    /// Space Grotesk's line box (ascent 0.984 em, descent 0.292 em) is far taller than its digits
    /// (0.714 em high, 0.014 em below the baseline): the number is laid out by its digits alone.
    static let digitHeight: CGFloat = 0.728
    private static let trimTop: CGFloat = 0.984 - 0.714
    private static let trimBottom: CGFloat = 0.292 - 0.014

    var count: Int
    var scratching: Bool
    var size: CGFloat
    @State private var bumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.22) {
            Text("\(count)")
                .font(WatchFont.sans(size, .bold))
                .tracking(-size * 0.04)
                .monospacedDigit()
                .foregroundStyle(scratching ? Twin.Palette.orange : .white)
                .contentTransition(.numericText(value: Double(count)))
                .keyframeAnimator(initialValue: 1.0, trigger: bumps) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(1.22, duration: 0.14)
                        SpringKeyframe(1, duration: 0.5)
                    }
                }
                .padding(.top, -size * Self.trimTop)
                .padding(.bottom, -size * Self.trimBottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 1 ? "SCRATCH" : "SCRATCHES")
                    .contentTransition(.identity)            // swaps at once (a crossfade doubles the letters as it slides)
                Text("TONIGHT")
            }
            .font(WatchFont.mono(10, bold: true))
            .tracking(0.6)
            .foregroundStyle(Twin.Palette.nightMuted)
            .fixedSize()
        }
        .animation(Twin.Motion.bouncy, value: count)
        .animation(Twin.Motion.spring, value: scratching)
        .onChange(of: count) { old, new in if new > old, !reduceMotion { bumps += 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "scratch" : "scratches") tonight")
    }
}

/// One line about the big screen: connected (cyan), can't reach it (orange, and why), or not
/// monitoring.
private struct ScreenStatus: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        let (text, color) = status
        HStack(spacing: 6) {
            if model.live != .off, model.screenLink == true {
                LiveDot(size: 6, color: color)
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            text
                .font(WatchFont.sans(13, .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .animation(Twin.Motion.spring, value: model.screenLink)
        .animation(Twin.Motion.spring, value: model.live)
        .accessibilityElement(children: .combine)
    }

    private var status: (Text, Color) {
        guard model.live != .off else { return (Text("Not monitoring"), Twin.Palette.nightMuted) }
        switch model.screenLink {
        case .some(true):
            return (Text("Connected to screen"), Twin.Palette.cyan)
        case .some(false):
            // Why, as the streamer reports it: a URL error code, "HTTP 401", "NO KEY", "WAIT 2s"…
            let why = model.screenDetail.isEmpty ? Text("") : Text(" (\(model.screenDetail))").font(WatchFont.mono(10))
            return (Text("Can’t reach screen\(why)"), Twin.Palette.orange)
        case .none:
            return (Text("Connecting to screen…"), Twin.Palette.nightMuted)
        }
    }
}
