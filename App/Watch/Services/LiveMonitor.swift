import Foundation
import CoreMotion
import HealthKit
import WatchKit
import EczemaKit

/// Live scratch detection: `CMMotionManager` at 50 Hz feeding the streaming `ScratchDetector`.
///
/// To keep running with the screen off it holds an `HKWorkoutSession`; if HealthKit says no it
/// falls back to a `WKExtendedRuntimeSession` (physical therapy, up to an hour), and failing that it
/// runs while the app is open. The simulator has no accelerometer: there a scripted synthetic
/// signal (`SimulatedSensor`) goes through the very same detector, and its episodes are marked
/// `.demo` so they never reach real data.
@MainActor
final class LiveMonitor: NSObject {
    enum Backing: String {
        case workout, extendedRuntime, foreground, simulated
        var label: String {
            switch self {
            case .workout: "Workout session"
            case .extendedRuntime: "Runtime session"
            case .foreground: "While open"
            case .simulated: "Simulated sensor"
            }
        }
    }

    enum Event {
        case started(Backing, Date)
        case backingChanged(Backing)
        case stopped(reason: String?)
        case window(WindowResult)
        case episodeStarted(EpisodeStart)
        case episodeEnded(DetectedEpisode)
    }

    /// Always called on the main actor.
    var onEvent: (@MainActor (Event) -> Void)?
    private(set) var isRunning = false
    private(set) var backing: Backing?

    private let motion = CMMotionManager()
    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var runtime: WKExtendedRuntimeSession?
    private var simulator: SimulatedSensor?
    private var pipe: DetectorPipe?

    /// The simulator (and very old hardware) has no accelerometer.
    var hasAccelerometer: Bool { motion.isAccelerometerAvailable }

    func start(model: ScratchModel, lastAlert: Date?) async {
        guard !isRunning else { return }
        isRunning = true
        let real = hasAccelerometer
        let pipe = DetectorPipe(model: model, source: real ? .live : .demo, lastAlert: lastAlert) { [weak self] events in
            Task { @MainActor in self?.deliver(events) }
        }
        self.pipe = pipe

        guard real else {
            let sim = SimulatedSensor()
            simulator = sim
            sim.start { samples in pipe.process(samples) }
            began(.simulated)
            return
        }

        var chosen: Backing = .foreground
        if await startWorkout() {
            chosen = .workout
        }
        guard isRunning, self.pipe === pipe else {
            // Stopped (or restarted) while HealthKit was asking: don't leave a session behind.
            if let w = workout { workout = nil; w.end() }
            return
        }
        if chosen != .workout, startRuntimeSession() {
            chosen = .extendedRuntime
        }
        startMotion(pipe)
        began(chosen)
    }

    func stop(reason: String? = nil) {
        guard isRunning else { return }
        isRunning = false
        motion.stopAccelerometerUpdates()
        simulator?.stop()
        simulator = nil
        if let w = workout { workout = nil; w.end() }
        if let r = runtime { runtime = nil; r.invalidate() }
        pipe?.finish()
        pipe = nil
        backing = nil
        onEvent?(.stopped(reason: reason))
    }

    /// The user answered a prompt: score the next windows with the updated model.
    func update(model: ScratchModel) { pipe?.update(model: model) }

    // MARK: - Pieces

    private func began(_ b: Backing) {
        backing = b
        onEvent?(.started(b, Date()))
    }

    private func deliver(_ events: [DetectorEvent]) {
        for e in events {
            switch e {
            case let .window(w): onEvent?(.window(w))
            case let .episodeStarted(s): onEvent?(.episodeStarted(s))
            case let .episodeEnded(d): onEvent?(.episodeEnded(d))
            }
        }
    }

    private func startMotion(_ pipe: DetectorPipe) {
        motion.accelerometerUpdateInterval = 1 / 50
        // The handler runs on the detector's own serial queue (a fresh operation queue per run).
        let queue = OperationQueue()
        queue.name = "com.jackyzhong.eczematwin.motion"
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = pipe.queue
        // CMAccelerometerData timestamps count from boot; turn them into wall-clock time.
        let bootOffset = Date().timeIntervalSinceReferenceDate - ProcessInfo.processInfo.systemUptime
        motion.startAccelerometerUpdates(to: queue) { data, _ in
            guard let d = data else { return }
            pipe.processOnQueue(MotionSample(t: bootOffset + d.timestamp, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z))
        }
    }

    private func startWorkout() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let type = HKObjectType.workoutType()
        do {
            try await health.requestAuthorization(toShare: [type], read: [])
        } catch {
            return false
        }
        guard health.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            session.delegate = self
            session.startActivity(with: Date())
            workout = session
            return true
        } catch {
            return false
        }
    }

    private func startRuntimeSession() -> Bool {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        runtime = session
        return true
    }

    fileprivate func workoutEnded(_ session: HKWorkoutSession, failed: Bool) {
        guard session === workout, isRunning else { return }
        workout = nil
        // Another workout took over or HealthKit stopped us: keep going on a runtime session if we can.
        if startRuntimeSession() {
            backing = .extendedRuntime
            onEvent?(.backingChanged(.extendedRuntime))
        } else {
            stop(reason: failed ? "Workout session failed" : nil)
        }
    }

    fileprivate func runtimeEnded(_ session: WKExtendedRuntimeSession) {
        guard session === runtime, isRunning else { return }
        runtime = nil
        backing = .foreground
        onEvent?(.backingChanged(.foreground))
    }
}

extension LiveMonitor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.workoutEnded(workoutSession, failed: false) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.workoutEnded(workoutSession, failed: true) }
    }
}

extension LiveMonitor: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in self.runtimeEnded(extendedRuntimeSession) }
    }
}

/// Owns the detector and the serial queue it lives on.
final class DetectorPipe: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.detector", qos: .userInitiated)
    private let detector: ScratchDetector
    private let emit: ([DetectorEvent]) -> Void

    init(model: ScratchModel, source: EpisodeSource, lastAlert: Date?, emit: @escaping ([DetectorEvent]) -> Void) {
        detector = ScratchDetector(model: model, source: source, lastAlert: lastAlert)
        self.emit = emit
    }

    /// Only from `queue` (the motion handler's operation queue runs on it).
    func processOnQueue(_ sample: MotionSample) {
        let events = detector.process(sample)
        if !events.isEmpty { emit(events) }
    }

    func process(_ samples: [MotionSample]) {
        queue.async {
            let events = self.detector.process(samples)
            if !events.isEmpty { self.emit(events) }
        }
    }

    func update(model: ScratchModel) { queue.async { self.detector.updateModel(model) } }

    func finish() {
        queue.async {
            let events = self.detector.finish()
            if !events.isEmpty { self.emit(events) }
        }
    }
}

/// A scripted wrist for the simulator: rest, scratching, typing, walking, an intense scratch,
/// played in real time on a loop (64 s) through the real detector.
final class SimulatedSensor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.simsensor")
    private var timer: DispatchSourceTimer?
    private let script: [MotionSample]
    private let loopLength: TimeInterval
    private var cursor = 0
    private var origin: TimeInterval = 0

    init() {
        var b = SyntheticMotion(start: 0, seed: 0x51A7)
        b.still(3)
        b.scratch(9, hz: 4.3, amplitude: 0.24)
        b.still(10)
        b.type(8)
        b.walk(10)
        b.still(10)
        b.scratch(8, hz: 5.4, amplitude: 0.62)
        b.still(6)
        script = b.samples
        loopLength = b.time
    }

    func start(deliver: @escaping ([MotionSample]) -> Void) {
        origin = Date().timeIntervalSinceReferenceDate
        cursor = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick(deliver) }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick(_ deliver: ([MotionSample]) -> Void) {
        guard !script.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        var batch: [MotionSample] = []
        while true {
            if cursor >= script.count { cursor = 0; origin += loopLength }
            let s = script[cursor]
            let t = origin + s.t
            if t > now { break }
            batch.append(MotionSample(t: t, x: s.x, y: s.y, z: s.z))
            cursor += 1
        }
        if !batch.isEmpty { deliver(batch) }
    }
}
