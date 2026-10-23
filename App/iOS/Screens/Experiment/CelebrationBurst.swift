import SwiftUI

/// A one-shot burst of little brand-colour stickers (ink-edged squares and strips) from the centre of the
/// view it overlays. Plays each time `trigger` changes; draws nothing the rest of the time.
struct CelebrationBurst: View {
    var trigger: Int
    var duration: Double = 1.7

    @State private var start: Date?

    private struct Particle {
        var angle: Double      // radians
        var speed: Double      // pt/s
        var spin: Double       // rad/s
        var size: CGSize
        var color: Color
        var delay: Double
    }

    private static let particles: [Particle] = {
        var rng = SystemRandomNumberGenerator()
        let colors = [Twin.Palette.pink, Twin.Palette.yellow, Twin.Palette.cyan, Twin.Palette.lime, Twin.Palette.orange]
        return (0..<46).map { i in
            // Mostly upwards and sideways, a few downwards.
            let base = -Double.pi / 2 + Double.random(in: -1.35...1.35, using: &rng)
            let angle = i % 6 == 0 ? Double.random(in: 0.3...2.8, using: &rng) : base
            let strip = i % 3 == 0
            return Particle(angle: angle,
                            speed: Double.random(in: 340...720, using: &rng),
                            spin: Double.random(in: -9...9, using: &rng),
                            size: strip ? CGSize(width: 6, height: 16) : CGSize(width: 11, height: 11),
                            color: colors[i % colors.count],
                            delay: Double.random(in: 0...0.08, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { ctx, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.45)
                let gravity = 1100.0
                for p in Self.particles {
                    let tt = t - p.delay
                    guard tt > 0 else { continue }
                    let drag = 1 - min(tt / duration, 1) * 0.35
                    let x = origin.x + cos(p.angle) * p.speed * tt * drag
                    let y = origin.y + sin(p.angle) * p.speed * tt * drag + 0.5 * gravity * tt * tt
                    let fade = max(0, min(1, (duration - tt) / 0.45))
                    let pop = min(1, tt / 0.12)
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * tt))
                    c.scaleBy(x: pop, y: pop)
                    let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                    let shape = Path(roundedRect: rect, cornerRadius: 1.5)
                    c.fill(shape, with: .color(p.color))
                    c.stroke(shape, with: .color(Twin.Palette.ink), lineWidth: 1.3)
                }
            }
        }
        .onChange(of: trigger) { _, _ in
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { start = nil }
        }
        .accessibilityHidden(true)
    }
}
