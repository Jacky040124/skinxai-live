import Foundation
@preconcurrency import CoreMotion
import EczemaKit

/// All-day detection without keeping the app awake: `CMSensorRecorder` records the accelerometer
/// at 50 Hz for 12 hours at a time (re-armed whenever the app opens), and the recording is read
/// back in 5-minute slices and analysed with the personal model.
///
/// Every read has a budget: how much recording it may read and how long it may take. A background
/// refresh gets a few seconds of CPU from watchOS, so it reads at most 15 minutes of recording;
/// opening the app reads up to 2 hours (off the main thread). Whatever is left is read next time.
final class BackgroundRecorder: @unchecked Sendable {
    static let recordingLength: TimeInterval = 12 * 3600
    static let sliceLength: TimeInterval = 5 * 60
    /// Recorded samples become readable a few minutes after the fact.
    static let dataLatency: TimeInterval = 180
    /// CMSensorRecorder keeps recorded data for 3 days.
    static let retention: TimeInterval = 3 * 86_400

    struct Budget: Sendable {
        /// Most recording one run reads.
        var recording: TimeInterval
        /// Most wall-clock time one run takes.
        var seconds: TimeInterval

        static let backgroundRefresh = Budget(recording: 15 * 60, seconds: 2.5)
        static let appOpen = Budget(recording: 2 * 3600, seconds: 20)
    }

    /// Stops a run early (background task expiring, app leaving the screen).
    final class Cancel: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func cancel() { lock.lock(); flag = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    struct Result: Sendable {
        var episodes: [DetectedEpisode]
        /// Read up to here; the next run starts here.
        var through: Date
    }

    /// false in the simulator and on watches without the recorder.
    static var isAvailable: Bool { CMSensorRecorder.isAccelerometerRecordingAvailable() }
    static var isDenied: Bool {
        let s = CMSensorRecorder.authorizationStatus()
        return s == .denied || s == .restricted
    }

    private lazy var recorder = CMSensorRecorder()
    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.recorder", qos: .utility)

    /// Starts a fresh 12-hour recording unless one started less than an hour ago.
    /// Returns the new end of the recording, or nil when nothing was (re)armed.
    func armIfNeeded(armedUntil: Date?, now: Date = Date()) -> Date? {
        guard Self.isAvailable, !Self.isDenied else { return nil }
        if let until = armedUntil, until.timeIntervalSince(now) > Self.recordingLength - 3600 { return nil }
        recorder.recordAccelerometer(forDuration: Self.recordingLength)
        return now.addingTimeInterval(Self.recordingLength)
    }

    /// Reads the recording from `from` on, within `budget`, and returns the episodes found and how
    /// far it got. nil when there is nothing new to read yet.
    func analyze(from start: Date, model: ScratchModel, budget: Budget, cancel: Cancel) async -> Result? {
        guard Self.isAvailable, !Self.isDenied else { return nil }
        let now = Date()
        let from = max(start, now.addingTimeInterval(-Self.retention))
        let end = min(now.addingTimeInterval(-Self.dataLatency), from.addingTimeInterval(budget.recording))
        guard end.timeIntervalSince(from) > 60 else { return nil }
        let recorder = self.recorder
        return await withCheckedContinuation { continuation in
            queue.async {
                let deadline = Date().addingTimeInterval(budget.seconds)
                func outOfTime() -> Bool { cancel.isCancelled || Date() >= deadline }
                let detector = ScratchDetector(model: model, source: .recorded)
                var found: [DetectedEpisode] = []
                var through = from
                var sliceStart = from
                while sliceStart < end, !outOfTime() {
                    let sliceEnd = min(sliceStart.addingTimeInterval(Self.sliceLength), end)
                    var cutAt: Date?
                    autoreleasepool {
                        guard let list = recorder.accelerometerData(from: sliceStart, to: sliceEnd) else { return }
                        var iterator = NSFastEnumerationIterator(list)
                        var count = 0
                        var last: Date?
                        while let item = iterator.next() {
                            guard let d = item as? CMRecordedAccelerometerData else { continue }
                            count += 1
                            if count % 1000 == 0, outOfTime() {
                                cutAt = last.map { $0.addingTimeInterval(0.001) } ?? sliceStart
                                return
                            }
                            let sample = MotionSample(date: d.startDate, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z)
                            found += detector.process(sample).episodes
                            last = d.startDate
                        }
                    }
                    if let cutAt {
                        through = cutAt
                        break
                    }
                    through = sliceEnd
                    sliceStart = sliceEnd
                }
                // Don't split a bout of scratching between two runs: if one is still going where
                // this run stops, the next run reads it again from its first window. (Unless it
                // began where this run began: then it is longer than a whole run, so close it.)
                if let pending = detector.pendingSince, pending > from.addingTimeInterval(1) {
                    through = min(through, pending)
                } else {
                    found += detector.finish().episodes
                }
                continuation.resume(returning: Result(episodes: found, through: through))
            }
        }
    }
}
