import SwiftUI

/// Today's ring on black: fills from zero when it appears, carries a tick at "your usual",
/// and when minutes are added the new stretch of ring glows white for a moment.
struct WatchRing<Center: View>: View {
    var progress: Double
    /// Where "your usual" sits on the ring (0...1), nil to hide the tick.
    var usualMark: Double?
    var color: Color
    var lineWidth: CGFloat = 14
    var delay: Double = 0.15
    @ViewBuilder var center: () -> Center

    @State private var shown: Double
    @State private var gainFrom: Double?
    @State private var glow: Double = 0
    @State private var markShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `startProgress`: where the ring stands when it appears (nil = empty, then it fills).
    init(progress: Double, startProgress: Double? = nil, usualMark: Double?, color: Color, lineWidth: CGFloat = 14,
         delay: Double = 0.15, @ViewBuilder center: @escaping () -> Center) {
        self.progress = progress
        self.usualMark = usualMark
        self.color = color
        self.lineWidth = lineWidth
        self.delay = delay
        self.center = center
        _shown = State(initialValue: startProgress ?? 0)
        _markShown = State(initialValue: startProgress != nil)
    }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = (d - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(Twin.Palette.nightTrack, lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                Circle()
                    .trim(from: 0, to: clamp(shown))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                if let from = gainFrom {
                    Circle()
                        .trim(from: clamp(from), to: clamp(shown))
                        .stroke(Color.white.opacity(glow), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .padding(lineWidth / 2)
                }
                if let usualMark {
                    let angle = Angle.degrees(clamp(usualMark) * 360 - 90)
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 1.2, style: .continuous).strokeBorder(Color.black, lineWidth: 1.2))
                        .frame(width: lineWidth + 5, height: 4)
                        .rotationEffect(angle)
                        .offset(x: r * cos(angle.radians), y: r * sin(angle.radians))
                        .scaleEffect(markShown ? 1 : 0.2)
                        .opacity(markShown ? 1 : 0)
                }
                center()
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if shown != progress { withAnimation(Twin.Motion.fill.delay(delay)) { shown = progress } }
            if !markShown { withAnimation(Twin.Motion.bouncy.delay(delay + 0.9)) { markShown = true } }
        }
        .onChange(of: progress) { old, new in
            if new > old + 0.0005, !reduceMotion {
                gainFrom = min(old, shown)
                glow = 0.95
                withAnimation(Twin.Motion.fill) { shown = new }
                withAnimation(.easeOut(duration: 1.4).delay(0.9)) { glow = 0 }
            } else {
                withAnimation(Twin.Motion.fill) { shown = new }
            }
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
