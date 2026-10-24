import SwiftUI

/// A one-shot burst of little brand-colour stickers (ink-edged squares and strips) that pops out from
/// behind the result card: most shoot up out of its top edge over the yellow top bar, a few spill out of
/// its bottom edge. Nothing is drawn over the card itself, so its headline stays readable the whole time.
/// Plays each time `trigger` changes; draws nothing the rest of the time.
struct CelebrationBurst: View {
    var trigger: Int
    /// The result card in this view's coordinates.
    var card: CGRect
    var duration: Double = 1.8

    @State private var start: Date?

    private struct Particle {
        var fromTop: Bool
        var along: Double      // 0…1 across the card's edge
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
        return (0..<60).map { i in
            let fromTop = i % 5 != 0
            // Up and out of the top edge, most of them peaking over the yellow top bar.
            let angle = fromTop
                ? -Double.pi / 2 + Double.random(in: -1.15...1.15, using: &rng)
                : Double.pi / 2 + Double.random(in: -1.1...1.1, using: &rng)
            let strip = i % 3 == 0
            return Particle(fromTop: fromTop,
                            along: Double.random(in: 0.06...0.94, using: &rng),
                            angle: angle,
                            speed: fromTop ? Double.random(in: 330...700, using: &rng) : Double.random(in: 140...300, using: &rng),
                            spin: Double.random(in: -9...9, using: &rng),
                            size: strip ? CGSize(width: 6, height: 16) : CGSize(width: 11, height: 11),
                            color: colors[(i + i / colors.count) % colors.count],
                            delay: Double.random(in: 0...0.14, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { ctx, _ in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                // Behind the card: nothing is drawn where it is (a little past its edge, for the pop).
                ctx.clip(to: Path(roundedRect: card.insetBy(dx: -4, dy: -4), cornerRadius: Twin.Radius.card + 4),
                         options: .inverse)
                let gravity = 1250.0
                for p in Self.particles {
                    let tt = t - p.delay
                    guard tt > 0 else { continue }
                    let origin = CGPoint(x: card.minX + card.width * p.along,
                                         y: p.fromTop ? card.minY + 12 : card.maxY - 12)
                    let drag = 1 - min(tt / duration, 1) * 0.35
                    let x = origin.x + cos(p.angle) * p.speed * tt * drag
                    let y = origin.y + sin(p.angle) * p.speed * tt * drag + 0.5 * gravity * tt * tt
                    let fade = max(0, min(1, (duration - tt) / 0.5))
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * tt))
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
