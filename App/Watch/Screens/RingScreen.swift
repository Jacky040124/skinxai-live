import SwiftUI
import EczemaKit

/// Default screen: today's scratching against your usual, episode counts, and live detection.
struct RingScreen: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tap the ring: the middle flips to "3.2× your usual" for a moment and the usual tick pops.
    @State private var showRatio = false
    @State private var flipBack: Task<Void, Never>?

    var body: some View {
        let today = model.today
        // Coming back from the alert, the ring resumes from where it was and ticks up from there.
        let from = model.ringResume
        GeometryReader { geo in
            // Ring + stats (26) + gap + control (36) share the height.
            let ring = min(geo.size.width * 0.64, geo.size.height - 26 - 10 - 36 - 2)
            VStack(spacing: 0) {
                WatchRing(progress: today.progress, startProgress: from?.progress, usualMark: today.usualMark,
                          color: today.aboveUsual ? Twin.Palette.orange : Twin.Palette.lime, lineWidth: 14,
                          highlightMark: showRatio) {
                    RingCenter(minutes: today.minutes, from: from?.minutes, ratio: today.ratio, showRatio: showRatio)
                }
                .frame(width: ring, height: ring)
                .contentShape(Circle())
                .onTapGesture { flip() }
                .onLongPressGesture(minimumDuration: 0.8) { model.presentDemoAlert() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Scratching today")
                .accessibilityValue(accessibilityValue(today))
                .accessibilityAction(named: "Ask if I was scratching") { model.presentDemoAlert() }

                StatsRow(episodes: today.episodes, intense: today.intense)
                    .padding(.top, 6)
                    .watchRise(from == nil ? 0.45 : 0.05, distance: 8)

                Spacer(minLength: 6)

                LiveControl()
                    .frame(maxWidth: 172)
                    .watchRise(from == nil ? 0.6 : 0.12, distance: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            // `-showRatio 1`: flip to the ratio once after the entrance (screenshots).
            guard UserDefaults.standard.bool(forKey: "showRatio") else { return }
            try? await Task.sleep(for: .seconds(1.6))
            flip()
        }
    }

    private func flip() {
        Haptics.tap()
        flipBack?.cancel()
        withAnimation(Twin.Motion.bouncy) { showRatio.toggle() }
        guard showRatio else { return }
        flipBack = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Twin.Motion.spring) { showRatio = false }
        }
    }

    private func accessibilityValue(_ t: TodaySummary) -> String {
        let minutes = Int(t.minutes.rounded())
        let usual = t.ratio >= 1.15 ? String(format: "%.1f times your usual", t.ratio) : "about your usual"
        return "\(minutes) minutes, \(usual). \(t.episodes) episodes, \(t.intense) intense."
    }
}

/// The counted number and its unit inside the ring; flips to the ratio against your usual.
private struct RingCenter: View {
    var minutes: Double
    var from: Double?
    var ratio: Double
    var showRatio: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WatchCountUp(value: minutes.rounded(), from: from?.rounded(), font: WatchFont.sans(42, .bold),
                             delay: 0.2, duration: 1.2)
                    .tracking(-1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("MIN TODAY")
                    .font(WatchFont.mono(9.5))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.nightMuted)
                    .offset(y: -2)
            }
            .opacity(showRatio ? 0 : 1)
            .scaleEffect(showRatio && !reduceMotion ? 0.7 : 1)
            .blur(radius: showRatio ? 4 : 0)

            VStack(spacing: 0) {
                Text(ratio.formatted(.number.precision(.fractionLength(1))) + "×")
                    .font(WatchFont.sans(36, .bold))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("YOUR USUAL")
                    .font(WatchFont.mono(9.5))
                    .tracking(0.6)
                    .foregroundStyle(Twin.Palette.nightMuted)
            }
            .opacity(showRatio ? 1 : 0)
            .scaleEffect(showRatio || reduceMotion ? 1 : 1.3)
            .blur(radius: showRatio ? 0 : 4)
        }
        .padding(.horizontal, 18)
    }
}

/// Episodes today (hand) and intense ones (orange flame).
struct StatsRow: View {
    var episodes: Int
    var intense: Int
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(episodes)")
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(episodes)))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(episodes) episodes")
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(intense)")
                    .contentTransition(.numericText(value: Double(intense)))
            }
            .foregroundStyle(Twin.Palette.orange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(intense) intense")
        }
        .font(WatchFont.sans(16, .bold))
        .monospacedDigit()
        .animation(Twin.Motion.bouncy, value: episodes)
        .animation(Twin.Motion.bouncy, value: intense)
    }
}

/// Start / stop live detection. Pink when off (the main action); a dark card with a cyan edge,
/// a breathing dot, the elapsed time and the live window strip while it runs.
struct LiveControl: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        let on = model.live.isOn
        Button { model.toggleLive() } label: {
            ZStack {
                switch model.live {
                case .off:
                    HStack(spacing: 7) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .symbolEffect(.variableColor.iterative, options: .nonRepeating, value: on)
                        Text("Start detecting")
                    }
                    .foregroundStyle(Twin.Palette.ink)
                    .transition(.blurReplace)
                case .starting:
                    HStack(spacing: 8) {
                        PixelSpinner(pixel: 3, color: Twin.Palette.ink)
                        Text("Starting…")
                    }
                    .foregroundStyle(Twin.Palette.ink)
                    .transition(.blurReplace)
                case let .on(since, backing):
                    LiveRunning(since: since, backing: backing, ticks: model.ticks)
                        .transition(.blurReplace)
                }
            }
            .font(WatchFont.sans(14, .bold))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(on ? Twin.Palette.nightCard : Twin.Palette.pink,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Twin.Palette.cyan.opacity(0.9) : .clear, lineWidth: 1.5))
            .animation(Twin.Motion.spring, value: model.live)
        }
        .buttonStyle(WatchPressStyle(scale: 0.95))
        .accessibilityLabel(on ? "Stop live detection" : "Start live scratch detection")
    }
}

private struct LiveRunning: View {
    var since: Date
    var backing: LiveMonitor.Backing
    var ticks: [WatchModel.LiveTick]

    var body: some View {
        HStack(spacing: 8) {
            LiveDot(size: 7)
            VStack(alignment: .leading, spacing: -1) {
                Text(backing == .simulated ? "SIM" : "LIVE")
                    .font(WatchFont.mono(10, bold: true))
                    .foregroundStyle(Twin.Palette.cyan)
                Text(since, style: .timer)
                    .font(WatchFont.mono(10))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .fixedSize()
            Spacer(minLength: 4)
            LiveStrip(ticks: ticks)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.white)
                .frame(width: 10, height: 10)
                .padding(.leading, 2)
        }
    }
}

/// The last windows the detector scored: height = how scratch-like (or how much motion),
/// orange when the window counted as scratching.
struct LiveStrip: View {
    var ticks: [WatchModel.LiveTick]
    private let slots = 10
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<max(0, slots - ticks.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.2)).frame(width: 4, height: 4)
            }
            ForEach(ticks) { t in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(t.scratch ? Twin.Palette.orange : Twin.Palette.cyan.opacity(0.5 + 0.5 * t.level))
                    .frame(width: 4, height: 4 + 16 * min(1, max(0, t.level)))
                    .transition(.asymmetric(insertion: .scale(scale: 0.2, anchor: .center).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}
