import SwiftUI
import EczemaKit

/// "Were you scratching?" — the watch's hero moment.
///
/// The face shakes once and buzzes hard, an orange hand tile scratches back and forth while ripple
/// rings run out of it and the screen glows in time. No / Yes: the tile turns into the answer, the
/// personal model learns, and the alert folds away to the ring, which ticks up on a Yes.
struct ScratchAlertView: View {
    let alert: ScratchAlert
    @EnvironmentObject var model: WatchModel
    @State private var answered: Bool?
    @State private var shake = 0
    @State private var shown = false
    @State private var born = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 175
            let tile = min(84, geo.size.height * (compact ? 0.34 : 0.42))
            ZStack {
                PulseGlow(born: born, answered: answered, reduceMotion: reduceMotion)
                    .frame(width: geo.size.width * 1.4, height: geo.size.width * 1.4)
                    .position(x: geo.size.width / 2, y: tile / 2 + 4)
                VStack(spacing: 0) {
                    PulseTile(born: born, answered: answered, reduceMotion: reduceMotion)
                        .frame(width: tile, height: tile)
                        .scaleEffect(shown ? 1 : 0.3)
                        .opacity(shown ? 1 : 0)
                        .padding(.top, 4)
                    Text("Were you\nscratching?")
                        .font(WatchFont.sans(compact ? 15 : 17, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, compact ? 9 : 13)
                        .watchRise(0.12, distance: 8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    HStack(spacing: 8) {
                        Button("No") { answer(false) }
                            .buttonStyle(WatchButtonStyle(fill: Twin.Palette.nightTrack, foreground: .white, height: compact ? 34 : 40,
                                                          radius: 14, fontSize: compact ? 15 : 16))
                            .accessibilityLabel("No, I wasn't scratching")
                        Button("Yes") { answer(true) }
                            .buttonStyle(WatchButtonStyle(fill: Twin.Palette.yellow, foreground: Twin.Palette.ink, height: compact ? 34 : 40,
                                                          radius: 14, fontSize: compact ? 15 : 16))
                            .accessibilityLabel("Yes, I was scratching")
                    }
                    .disabled(answered != nil)
                    .padding(.horizontal, 10)
                    .watchRise(0.22, distance: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-5, duration: 0.06)
                CubicKeyframe(5, duration: 0.08)
                CubicKeyframe(-4, duration: 0.08)
                CubicKeyframe(4, duration: 0.08)
                CubicKeyframe(-2, duration: 0.07)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .onAppear {
            born = Date()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            if !reduceMotion { shake += 1 }
        }
        .task {
            // `-autoAnswer yes|no`: answers by itself (recording the whole moment in scripts/video).
            guard let auto = UserDefaults.standard.string(forKey: "autoAnswer") else { return }
            try? await Task.sleep(for: .milliseconds(2600))
            answer(auto.lowercased().hasPrefix("y"))
        }
    }

    private func answer(_ yes: Bool) {
        guard answered == nil else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { answered = yes }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            model.answer(yes)
        }
    }
}

/// The orange hand tile with ripple rings; it becomes a check (lime) or a cross after the answer.
private struct PulseTile: View {
    var born: Date
    var answered: Bool?
    var reduceMotion: Bool
    private let period = 1.8
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: answered != nil || dimmed)) { context in
            let t = max(0, context.date.timeIntervalSince(born))
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let phase = ((t / period) + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Twin.Palette.orange, lineWidth: 2)
                        .scaleEffect(reduceMotion ? 1.12 : 1 + 0.62 * phase)
                        .opacity(answered != nil ? 0 : (reduceMotion ? 0.45 : 0.9) * (1 - phase))
                }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white, lineWidth: 2))
                    .scaleEffect(answered == nil ? 1 : 1.06)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .rotationEffect(.degrees(answered == nil && !reduceMotion ? wiggle(t) : 0), anchor: .bottom)
                    .offset(x: answered == nil && !reduceMotion ? wiggle(t) * 0.18 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch answered {
        case .none: Twin.Palette.orange
        case .some(true): Twin.Palette.lime
        case .some(false): Twin.Palette.nightTrack.opacity(1)
        }
    }

    private var symbol: String {
        switch answered {
        case .none: "hand.raised.fingers.spread.fill"
        case .some(true): "checkmark"
        case .some(false): "xmark"
        }
    }

    /// A short burst of back-and-forth (about 6 Hz) at the start of every ripple, like scratching.
    private func wiggle(_ t: Double) -> Double {
        let local = t.truncatingRemainder(dividingBy: period)
        guard local < 0.75 else { return 0 }
        let envelope = sin(.pi * local / 0.75)
        return 11 * envelope * sin(2 * .pi * 6 * local)
    }
}

/// The screen pulses: a soft orange glow behind the tile that breathes with the ripples.
private struct PulseGlow: View {
    var born: Date
    var answered: Bool?
    var reduceMotion: Bool
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: answered != nil || reduceMotion || dimmed)) { context in
            let t = max(0, context.date.timeIntervalSince(born))
            let phase = (t / 1.8).truncatingRemainder(dividingBy: 1)
            let strength = answered != nil ? 0 : (reduceMotion ? 0.3 : 0.2 + 0.32 * pow(1 - phase, 2))
            RadialGradient(colors: [Twin.Palette.orange.opacity(strength), .clear], center: .center, startRadius: 4, endRadius: 120)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
