import Foundation
import EczemaKit

/// Streams live wrist motion and scratch events to the big-screen relay
/// (`https://<TwinLiveHost>/api/ingest`, Bearer `TwinLiveKey`), a few times a second.
///
/// Motion goes out as one number per sample (how hard the wrist moves, gravity removed, in g)
/// at 25 Hz; detector windows and episode start/end events go with it. The watch reaches the
/// internet through the paired iPhone (or Wi-Fi); a failed send keeps the events and drops old motion.
final class LiveStreamer: @unchecked Sendable {
    static let shared = LiveStreamer()

    /// Called on the main queue: true = the last send reached the relay, false = it failed.
    var onStatus: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.streamer")
    private let endpoint: URL?
    private let key: String?
    private var samples: [[Double]] = []
    private var windows: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var gravity: (Double, Double, Double)?
    private var decimate = false
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var running = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Seconds between Apple's reference date (2001) and the Unix epoch.
    private static let unixOffset: TimeInterval = 978_307_200

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["TwinLiveHost"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let k = (info["TwinLiveKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        endpoint = host.isEmpty || host.hasPrefix("$(") ? nil : URL(string: "https://\(host)/api/ingest")
        key = k.isEmpty || k.hasPrefix("$(") ? nil : k
    }

    var isConfigured: Bool { endpoint != nil && key != nil }

    func start() {
        queue.async {
            guard self.isConfigured, !self.running else { return }
            self.running = true
            self.samples.removeAll(); self.windows.removeAll(); self.events.removeAll(); self.gravity = nil
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.3, repeating: .milliseconds(300), leeway: .milliseconds(40))
            t.setEventHandler { [weak self] in self?.flush() }
            t.resume()
            self.timer = t
        }
    }

    func stop() {
        queue.async {
            guard self.running else { return }
            self.flush(force: true)
            self.timer?.cancel()
            self.timer = nil
            self.running = false
        }
    }

    // MARK: - Input (any thread)

    func add(_ sample: MotionSample) {
        queue.async { self.take(sample) }
    }

    func add(_ batch: [MotionSample]) {
        queue.async { for s in batch { self.take(s) } }
    }

    func add(_ events: [DetectorEvent]) {
        queue.async {
            guard self.running else { return }
            for e in events {
                switch e {
                case let .window(w):
                    let f = w.features
                    self.windows.append(["t": f.start + Self.unixOffset, "p": round3(w.probability), "scratch": w.isScratch,
                                         "strength": round3(f.strength), "hz": round3(f.dominantHz)])
                case let .episodeStarted(s):
                    self.events.append(["type": "start", "id": s.id.uuidString, "t": s.start.timeIntervalSince1970,
                                        "hz": round3(s.meanHz), "intense": false])
                case let .episodeEnded(d):
                    let ep = d.episode
                    self.events.append(["type": "end", "id": ep.id.uuidString, "t": ep.start.timeIntervalSince1970,
                                        "end": ep.end.timeIntervalSince1970, "seconds": round3(ep.duration),
                                        "intense": ep.intense, "hz": round3(ep.meanHz)])
                }
            }
        }
    }

    // MARK: - Private (on `queue`)

    private func take(_ s: MotionSample) {
        guard running else { return }
        // Slow gravity estimate; what is left is the wrist's own motion.
        if let g = gravity {
            gravity = (g.0 + (s.x - g.0) * 0.04, g.1 + (s.y - g.1) * 0.04, g.2 + (s.z - g.2) * 0.04)
        } else {
            gravity = (s.x, s.y, s.z)
        }
        decimate.toggle()
        guard decimate, let g = gravity else { return }          // 50 Hz in, 25 Hz out
        let dx = s.x - g.0, dy = s.y - g.1, dz = s.z - g.2
        let m = (dx * dx + dy * dy + dz * dz).squareRoot()
        samples.append([round3(s.t + Self.unixOffset), round4(m)])
        if samples.count > 25 * 20 { samples.removeFirst(samples.count - 25 * 20) }   // keep 20 s at most
    }

    private func flush(force: Bool = false) {
        guard let endpoint, let key, !inFlight else { return }
        guard !samples.isEmpty || !events.isEmpty || force else { return }
        let sendSamples = samples, sendWindows = windows, sendEvents = events
        samples.removeAll(keepingCapacity: true); windows.removeAll(); events.removeAll()
        let body: [String: Any] = ["device": "watch", "live": running && !force, "sentAt": Date().timeIntervalSince1970,
                                   "samples": sendSamples, "windows": sendWindows, "events": sendEvents]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        req.httpBody = data
        inFlight = true
        session.dataTask(with: req) { [weak self] _, response, error in
            guard let self else { return }
            let ok = error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200
            self.queue.async {
                self.inFlight = false
                if !ok { self.events = sendEvents + self.events }      // keep events; old motion is useless
            }
            DispatchQueue.main.async { self.onStatus?(ok) }
        }.resume()
    }
}

private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
private func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
