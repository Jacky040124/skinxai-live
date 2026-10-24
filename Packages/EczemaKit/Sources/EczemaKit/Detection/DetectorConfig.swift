import Foundation

/// One accelerometer reading from the wrist, in g, gravity included.
public struct MotionSample: Sendable, Hashable, Codable {
    /// Seconds since the reference date (`Date.timeIntervalSinceReferenceDate`).
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public var z: Double

    public init(t: TimeInterval, x: Double, y: Double, z: Double) {
        self.t = t; self.x = x; self.y = y; self.z = z
    }

    public init(date: Date, x: Double, y: Double, z: Double) {
        self.init(t: date.timeIntervalSinceReferenceDate, x: x, y: y, z: z)
    }

    public var date: Date { Date(timeIntervalSinceReferenceDate: t) }
}

/// Settings of the scratch detector (SPEC §5). The defaults are the tuned values; tests use them too.
public struct DetectorConfig: Sendable, Hashable {
    /// Accelerometer rate the detector expects (CMMotionManager and CMSensorRecorder both give 50 Hz).
    public var sampleRate: Double = 50
    /// Analysis window and hop: 3-second windows every 1.5 seconds.
    public var windowSeconds: Double = 3
    public var hopSeconds: Double = 1.5
    /// Movement gate: the window counts as "moving" when the largest per-axis SD is above this (g).
    public var movementGate: Double = 0.02
    /// Band searched for the back-and-forth rate (autocorrelation peaks), Hz.
    public var rateBand: ClosedRange<Double> = 1.5...10
    /// Band that scratching usually lives in (in-band power score), Hz.
    public var scratchBand: ClosedRange<Double> = 2.5...7
    /// A pure rhythm also peaks at 2x and 3x its period: take the first peak at least this high
    /// relative to the highest one.
    public var peakFraction: Double = 0.85
    /// Window probability at or above which the window counts as scratching.
    public var threshold: Double = 0.5
    /// Episodes whose mean motion SD is at least this are "intense" (g).
    public var intenseSD: Double = 0.35
    /// Buzz at most once per this many seconds.
    public var alertCooldown: TimeInterval = 45
    /// A hole in the sample stream longer than this ends the current episode and restarts the windows.
    public var maxSampleGap: TimeInterval = 0.5
    /// Scratch windows in a row needed to start an episode (2 = about 4.5 s of scratching, 1 = 3 s).
    public var minWindows: Int = 2
    /// Windows moving harder than this (g) never count as scratching (waving, big arm moves).
    public var maxStrength: Double = .infinity

    public init() {}

    public static let standard = DetectorConfig()

    /// Live detection on the wrist (stage demo + real use): reacts after one 3 s window, lets gentler
    /// scratching through, and ignores big arm movements such as waving.
    public static let live: DetectorConfig = {
        var c = DetectorConfig()
        c.movementGate = 0.012
        c.threshold = 0.42
        c.minWindows = 1
        c.maxStrength = 0.9
        c.alertCooldown = 20
        return c
    }()

    /// Samples per window (150 at 50 Hz).
    public var windowLength: Int { max(8, Int((windowSeconds * sampleRate).rounded())) }
    /// Samples per hop (75 at 50 Hz).
    public var hopLength: Int { max(1, Int((hopSeconds * sampleRate).rounded())) }
}
