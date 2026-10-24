import SwiftUI
import WatchKit

/// Watch typography. Same faces as the phone (Space Grotesk for reading, Space Mono for what the
/// machine writes) at fixed sizes: the watch layouts are measured to the point.
enum WatchFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", fixedSize: size).weight(weight)
    }
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", fixedSize: size)
    }
}

/// Watch haptics (richer than the shared `Haptics`).
enum WatchHaptic {
    static func play(_ type: WKHapticType) { WKInterfaceDevice.current().play(type) }

    /// The scratch alert: a strong double knock.
    static func scratchAlert() {
        play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { play(.retry) }
    }
}

/// Watch button: brand fill, a squash and a click on press.
struct WatchButtonStyle: ButtonStyle {
    var fill: Color = Twin.Palette.pink
    var foreground: Color = Twin.Palette.ink
    var height: CGFloat = 40
    var radius: CGFloat = 12
    var fontSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(WatchFont.sans(fontSize, .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: shape)
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.22 : 0)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// Press feedback without a fill (cards, rows, the ring).
struct WatchPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// Small brand tile with an SF Symbol in ink (the watch version of a sticker icon).
struct WatchTile: View {
    var symbol: String
    var fill: Color = Twin.Palette.orange
    var size: CGFloat = 16
    /// Ink on brand colors; pass `.white` on the dark track color.
    var symbolColor: Color = Twin.Palette.ink
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.58, weight: .bold))
            .foregroundStyle(symbolColor)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous))
    }
}

/// The top-left title that sits on the same line as the system clock.
/// `flash` briefly replaces it with feedback ("+1 logged") and slides back.
struct WatchTitle: View {
    var text: String
    var flash: WatchFlash? = nil
    var live = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            if let flash {
                HStack(spacing: 4) {
                    Image(systemName: flash.symbol).font(.system(size: 12, weight: .heavy))
                    Text(flash.text).font(WatchFont.sans(15, .bold))
                }
                .foregroundStyle(flash.color)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(flash.id)
            } else {
                HStack(spacing: 5) {
                    Text(text)
                        .font(WatchFont.sans(17, .bold))
                        .foregroundStyle(Twin.Palette.yellow)
                        .id(text)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                    if live { LiveDot(size: 6).transition(.scale.combined(with: .opacity)) }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Twin.Motion.spring, value: flash?.id)
        .animation(Twin.Motion.spring, value: live)
        .animation(Twin.Motion.spring, value: text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Feedback shown in the title row after an answer.
struct WatchFlash: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var symbol: String
    var color: Color

    static let logged = WatchFlash(text: "+1 logged", symbol: "checkmark", color: Twin.Palette.lime)
    static let ignored = WatchFlash(text: "Not counted", symbol: "xmark", color: .white)
    /// A Yes that teaches the model but isn't real data (the simulator's wrist in real data mode).
    static let learned = WatchFlash(text: "Learned", symbol: "sparkles", color: Twin.Palette.cyan)
}

/// A cyan dot that breathes while live detection runs (the only loop on the ring screen).
struct LiveDot: View {
    var size: CGFloat = 8
    var color: Color = Twin.Palette.cyan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: dimmed)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t / 1.6).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle().fill(color.opacity(reduceMotion ? 0.35 : 0.5 * (1 - phase)))
                    .scaleEffect(reduceMotion ? 1.6 : 1 + 1.4 * phase)
                Circle().fill(color)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// `.riseIn` that keeps only the fade when Reduce Motion is on.
struct WatchRise: ViewModifier {
    var delay: Double
    var distance: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.riseIn(delay, distance: reduceMotion ? 0 : distance)
    }
}

extension View {
    func watchRise(_ delay: Double = 0, distance: CGFloat = 10) -> some View {
        modifier(WatchRise(delay: delay, distance: distance))
    }
}
