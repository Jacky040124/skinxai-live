import Foundation
import EczemaKit

/// `-liveSim 1`: a built-in stand-in for the watch, so screenshots and videos work without one.
/// Tracking starts 1 s after launch; a scratch comes about every 6 s and lasts 2–4 s (the first
/// 4.5 s in, 3 s long). It sends what the watch sends through the relay (a batch every 0.3 s,
/// a detector window every 0.5 s, episode start/end events) and the batches go through the very
/// same rules as the relay's. Deterministic, no network.
///
/// `-liveSimStop <seconds>`: the stand-in taps Stop that long after tracking started
/// (a last batch with `live: false`).
/// `-liveSimQuiet <seconds>`: the stand-in goes silent that long after tracking started (a Wi-Fi
/// stall, or a Stop whose last batch never arrived); `-liveSimQuietFor <seconds>`: for that long,
/// then it carries on (default: for good).
@MainActor
final class LiveSimulator {
    var onBatch: ((LiveBatch) -> Void)?

    private let stopAfter: TimeInterval?
    private let quiet: Range<TimeInterval>?
    /// When tracking starts; seconds below are counted from here.
    private var origin: Date?
    private var loop: Task<Void, Never>?
    private var nextWindow: TimeInterval = 0
    /// The next wrist-motion value to send (25 a second, like the watch).
    private var nextSample: TimeInterval = 0
    private let scratches: [(start: TimeInterval, end: TimeInterval)]
    private var index = 0
    private var inScratch = false
    private var stopped = false

    private static let scratchWindow = LiveBatch.Window(scratch: true, p: 0.93, hz: 3.8, strength: 0.42)
    private static let calmWindow = LiveBatch.Window(scratch: false, p: 0.03, hz: 0, strength: 0.012)

    init(stopAfter: TimeInterval?, quietAt: TimeInterval? = nil, quietFor: TimeInterval? = nil) {
        self.stopAfter = stopAfter
        quiet = quietAt.map { $0..<($0 + (quietFor ?? .infinity)) }
        // The prototype's seeded generator (`rng(seed)`): same night every run.
        var seed: UInt32 = 11
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
        var list: [(TimeInterval, TimeInterval)] = []
        var start = 4.5
        for i in 0..<2_000 {
            let length = i == 0 ? 3.0 : 2 + 2 * random()
            list.append((start, start + length))
            start += 5.2 + 1.6 * random()
        }
        scratches = list
    }

    func start() {
        guard loop == nil, !stopped else { return }
        if origin == nil { origin = Date().addingTimeInterval(1) }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.flush()
            }
        }
    }

    private func flush() {
        guard let origin, !stopped else { return }
        let t = Date().timeIntervalSince(origin)
        guard t >= 0 else { return }
        if let stopAfter, t >= stopAfter {
            stopped = true
            loop?.cancel()
            loop = nil
            onBatch?(LiveBatch(live: false))
            return
        }
        if let quiet, quiet.contains(t) { return }
        var windows: [LiveBatch.Window] = []
        var events: [LiveBatch.Event] = []
        if t - nextWindow > 5 { nextWindow = (t / 0.5).rounded(.down) * 0.5 }   // back from a pause
        while nextWindow <= t, index < scratches.count {
            let w = nextWindow
            nextWindow += 0.5
            let current = scratches[index]
            if inScratch, w >= current.end {
                inScratch = false
                let seconds = current.end - current.start
                events.append(LiveBatch.Event(.end, hz: 3.8, intense: seconds > 3, seconds: seconds))
                index += 1
            }
            if !inScratch, index < scratches.count, w >= scratches[index].start {
                inScratch = true
                windows.append(Self.scratchWindow)
                events.append(LiveBatch.Event(.start, hz: 3.8))
                continue
            }
            windows.append(inScratch ? Self.scratchWindow : Self.calmWindow)
        }
        // Wrist motion, 25 values a second: a still wrist (about 0.01 g) and, during a scratch, a hand
        // moving back and forth about 4 times a second (0.15–0.85 g).
        if t - nextSample > 5 { nextSample = (t / 0.04).rounded(.down) * 0.04 }
        var motion: [Double] = []
        while nextSample <= t {
            let s = nextSample
            nextSample += 0.04
            let noise = Self.noise(s)
            let scratch = scratches.contains { s >= $0.start && s < $0.end }
            motion.append(scratch ? max(0.05, 0.5 + 0.32 * sin(2 * .pi * 4.2 * s) + 0.08 * (noise - 0.5))
                                  : 0.008 + 0.012 * noise)
        }
        onBatch?(LiveBatch(live: true, windows: windows, events: events, motion: motion))
    }

    /// A fixed pseudo-random value in 0..<1 for a time (same run every launch).
    private static func noise(_ s: TimeInterval) -> Double {
        let x = sin(s * 12.9898 * 25 + 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
