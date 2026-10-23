import Foundation
import CoreMotion
import EczemaKit

/// All-day detection without keeping the app awake: `CMSensorRecorder` records the accelerometer
/// at 50 Hz for 12 hours at a time (re-armed whenever the app opens), and the recording is read
/// back and analysed in 1-hour slices with the personal model.
final class BackgroundRecorder: @unchecked Sendable {
    static let recordingLength: TimeInterval = 12 * 3600
    static let sliceLength: TimeInterval = 3600
    /// Recorded samples become readable a few minutes after the fact.
    static let dataLatency: TimeInterval = 180

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

    /// Reads the recording from `from` up to a few minutes ago, one hour at a time (at most
    /// `maxSlices` hours per call), and returns the episodes found and how far it got.
    func analyze(from: Date, model: ScratchModel, maxSlices: Int) async -> (episodes: [DetectedEpisode], through: Date)? {
        guard Self.isAvailable, !Self.isDenied else { return nil }
        let end = Date().addingTimeInterval(-Self.dataLatency)
        guard end.timeIntervalSince(from) > 60 else { return nil }
        let recorder = self.recorder
        return await withCheckedContinuation { continuation in
            queue.async {
                let detector = ScratchDetector(model: model, source: .recorded)
                var found: [DetectedEpisode] = []
                var sliceStart = from
                var slices = 0
                while sliceStart < end && slices < maxSlices {
                    let sliceEnd = min(sliceStart.addingTimeInterval(Self.sliceLength), end)
                    autoreleasepool {
                        if let list = recorder.accelerometerData(from: sliceStart, to: sliceEnd) {
                            var iterator = NSFastEnumerationIterator(list)
                            while let item = iterator.next() {
                                guard let d = item as? CMRecordedAccelerometerData else { continue }
                                let sample = MotionSample(date: d.startDate, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z)
                                found += detector.process(sample).episodes
                            }
                        }
                    }
                    sliceStart = sliceEnd
                    slices += 1
                }
                found += detector.finish().episodes
                continuation.resume(returning: (found, sliceStart))
            }
        }
    }
}
