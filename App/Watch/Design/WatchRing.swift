import SwiftUI

/// Today's ring on black, drawn from one minutes value: the arc is `minutes / scale` and the
/// middle gets the very same `minutes`, so while it animates the number and the arc can never
/// disagree. It carries a tick at "your usual", and when minutes are added the new stretch of
/// ring glows white for a moment (`gainID` changes, the stretch starts at `gainFrom`).
struct WatchRing<Center: View>: View, Animatable {
    var minutes: Double
    /// Minutes at which the ring is full.
    var scale: Double
    /// Where "your usual" sits on the ring (0...1), nil to hide the tick.
    var usualMark: Double?
    var color: Color
    var lineWidth: CGFloat = 14
    /// Start of the stretch that glows; a new `gainID` plays the glow.
    var gainFrom: Double = 0
    var gainID = 0
    var markShown = true
    /// Pops the usual tick (while the middle shows the ratio).
    var highlightMark = false
    @ViewBuilder var center: (Double) -> Center

    var animatableData: Double {
        get { minutes }
        set { minutes = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = (d - lineWidth) / 2
            let progress = fraction(minutes)
            ZStack {
                Circle()
                    .stroke(Twin.Palette.nightTrack, lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                arc(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                arc(from: min(fraction(gainFrom), progress), to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                    // The stretch starts right at the gain (never slides there with the fill); its
                    // end follows `minutes` frame by frame.
                    .transaction { $0.animation = nil }
                    .keyframeAnimator(initialValue: 0.0, trigger: gainID) { content, glow in
                        content.opacity(glow)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(0.9, duration: 0.25)
                            LinearKeyframe(0.9, duration: 0.75)
                            CubicKeyframe(0, duration: 1.2)
                        }
                    }
                if let usualMark {
                    let angle = Angle.degrees(min(max(usualMark, 0), 1) * 360 - 90)
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(highlightMark ? Twin.Palette.yellow : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 1.2, style: .continuous).strokeBorder(Color.black, lineWidth: 1.2))
                        .frame(width: lineWidth + 5, height: highlightMark ? 6 : 4)
                        .scaleEffect(markShown ? 1 : 0.2)
                        .rotationEffect(angle)
                        .offset(x: r * cos(angle.radians), y: r * sin(angle.radians))
                        .opacity(markShown ? 1 : 0)
                        .animation(Twin.Motion.bouncy, value: highlightMark)
                }
                center(minutes)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fraction(_ m: Double) -> Double { scale > 0 ? min(max(m / scale, 0), 1) : 0 }

    private func arc(from: Double, to: Double) -> some Shape { Circle().trim(from: from, to: max(from, to)) }
}
