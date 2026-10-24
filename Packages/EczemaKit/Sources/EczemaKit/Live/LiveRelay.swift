import Foundation

// The phone's side of the live relay (`wss://eczema-twin-live.zhongzhenyu190.workers.dev/api/live`):
// what one message says (`LiveRelayMessage`, `LiveBatch`) and the rules that turn the stream into
// "tracking", "scratching" and tonight's count (`LiveRelayState`). Pure and clock-free: every call
// takes `now`, so the rules can be replayed from a recording in tests.

/// One text frame from the relay.
public enum LiveRelayMessage: Sendable, Equatable {
    /// What the watch sent a moment ago (it posts a few times a second while it tracks sleep).
    case batch(LiveBatch)
    /// Tonight's episodes were cleared on the relay (`POST /api/reset`).
    case reset
    /// `hello`, `pong`, `label`: nothing for the rules, but proof that the socket is alive.
    case other

    /// Reads one frame. nil when it isn't a JSON object with a string `type`.
    public static func parse(_ data: Data) -> LiveRelayMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        switch type {
        case "batch": return .batch(LiveBatch(json: dict))
        case "reset": return .reset
        default: return .other
        }
    }

    public static func parse(_ text: String) -> LiveRelayMessage? { parse(Data(text.utf8)) }
}

/// The parts of a relay batch the phone uses: `{live, windows: [{p, scratch, hz, strength}],
/// events: [{type: "start"|"end", hz, intense, seconds}]}`. Raw motion (`samples`, `raw`) is
/// ignored on purpose: the monitor shows the watch's decision, never wrist motion.
public struct LiveBatch: Sendable, Equatable {
    /// One detector window (3 s of motion, a new one every 0.5 s on the live preset).
    public struct Window: Sendable, Equatable {
        public var scratch: Bool
        public var p: Double?
        public var hz: Double?
        public var strength: Double?

        public init(scratch: Bool, p: Double? = nil, hz: Double? = nil, strength: Double? = nil) {
            self.scratch = scratch
            self.p = p
            self.hz = hz
            self.strength = strength
        }

        /// `passes(w)` of the big-screen monitor with its default thresholds (no `?minp`, `?maxs`,
        /// `?mins`): the watch flagged the window as scratching.
        public var passes: Bool { scratch && (p ?? 1) >= 0 && (strength ?? 0) >= 0 }
    }

    /// An episode boundary decided on the watch.
    public struct Event: Sendable, Equatable {
        public enum Kind: String, Sendable { case start, end }
        public var kind: Kind
        public var hz: Double?
        public var intense: Bool
        public var seconds: Double?

        public init(_ kind: Kind, hz: Double? = nil, intense: Bool = false, seconds: Double? = nil) {
            self.kind = kind
            self.hz = hz
            self.intense = intense
            self.seconds = seconds
        }
    }

    /// The watch's `live` flag: false in the last batch after Stop. nil when the sender left it out
    /// (counts as live: tracking only ends on an explicit `false`).
    public var live: Bool?
    public var windows: [Window]
    public var events: [Event]

    public init(live: Bool? = true, windows: [Window] = [], events: [Event] = []) {
        self.live = live
        self.windows = windows
        self.events = events
    }

    /// Lenient like the web page: missing or odd fields are skipped, never fatal.
    init(json: [String: Any]) {
        live = Self.bool(json["live"])
        windows = (json["windows"] as? [Any] ?? []).compactMap { item in
            guard let w = item as? [String: Any] else { return nil }
            return Window(scratch: Self.bool(w["scratch"]) ?? false, p: Self.number(w["p"]),
                          hz: Self.number(w["hz"]), strength: Self.number(w["strength"]))
        }
        events = (json["events"] as? [Any] ?? []).compactMap { item in
            guard let e = item as? [String: Any], let type = e["type"] as? String,
                  let kind = Event.Kind(rawValue: type) else { return nil }
            return Event(kind, hz: Self.number(e["hz"]), intense: Self.bool(e["intense"]) ?? false,
                         seconds: Self.number(e["seconds"]))
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.doubleValue != 0 }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }
}

/// Tonight as the phone sees it through the relay. A port of the big-screen monitor's rules
/// (`web/monitor.js`, `take()`) plus the session rules of the stage build (STAGE-SPEC §4):
///
/// - a window with `scratch == true` keeps "scratching" for 1.2 s;
/// - an event `start` starts an episode (count + 1) when the last window was a scratch; otherwise
///   the start waits for the next scratch window, and an `end` before that cancels it. `end` ends it;
/// - **tracking** = a batch arrived in the last 3.5 s and its `live` wasn't `false`;
/// - a **new session** (count from 0) starts when batches resume after ≥ 60 s of silence or after a
///   `live: false` batch;
/// - the **watch stopped** = a `live: false` batch, or 8 s without batches while a session runs.
public struct LiveRelayState: Sendable {
    public struct Episode: Sendable, Equatable, Identifiable {
        /// 1, 2, 3 … in the order the episodes started tonight.
        public let id: Int
        public let start: Date
        /// nil while it is still going on.
        public var end: Date?
        /// The watch's verdict, known when the episode ends.
        public var intense: Bool
    }

    /// What a call changed, for side effects (closing the monitor, a pop on the count).
    public enum Change: Sendable, Equatable {
        case sessionStarted
        case episodeStarted(Int)
        case episodeEnded(Int)
        case watchStopped
    }

    public static let trackingWindow: TimeInterval = 3.5
    public static let scratchHold: TimeInterval = 1.2
    public static let stopAfter: TimeInterval = 8
    public static let newSessionAfter: TimeInterval = 60

    /// Episodes started in this session.
    public private(set) var count = 0
    /// This session's episodes, oldest first.
    public private(set) var episodes: [Episode] = []
    /// When this session began (moved to the reset time by `reset(at:)`).
    public private(set) var startedAt: Date?
    public private(set) var lastBatchAt: Date?
    public private(set) var lastBatchLive = false
    /// A session runs from its first batch until the watch stops.
    public private(set) var isRunning = false

    /// No session yet, or the last one ended with `live: false`: the next live batch starts a new one.
    private var needsNewSession = true
    private var scratchUntil: Date?
    /// monitor.js `scratching`: between an accepted `start` and its `end`.
    private var episodeOpen = false
    /// monitor.js `ignoring`: a `start` came while the last window wasn't a scratch.
    private var ignoring = false
    /// monitor.js `passes(lastWin)`.
    private var lastWindowPassed = false
    /// Silence is only counted while the phone can hear the relay (see `resumeListening(at:)`).
    private var listeningSince: Date?

    public init() {}

    /// A batch arrived in the last 3.5 s and its `live` wasn't false.
    public func isTracking(at now: Date) -> Bool {
        guard lastBatchLive, let last = lastBatchAt else { return false }
        return now.timeIntervalSince(last) < Self.trackingWindow
    }

    /// An episode is going on, or a scratch window arrived in the last 1.2 s.
    public func isScratching(at now: Date) -> Bool {
        guard isRunning else { return false }
        if episodeOpen { return true }
        if let until = scratchUntil { return now < until }
        return false
    }

    /// One relay batch received at `now`.
    @discardableResult
    public mutating func take(_ batch: LiveBatch, at now: Date) -> [Change] {
        var changes: [Change] = []
        let live = batch.live != false
        if live {
            let silence = lastBatchAt.map { now.timeIntervalSince($0) } ?? .infinity
            if needsNewSession || silence >= Self.newSessionAfter {
                count = 0
                episodes = []
                startedAt = now
                episodeOpen = false
                ignoring = false
                scratchUntil = nil
                lastWindowPassed = false
                needsNewSession = false
                changes.append(.sessionStarted)
            }
            isRunning = true
        }
        lastBatchAt = now
        lastBatchLive = live

        if isRunning {
            // monitor.js take(): every window first, then every event.
            for window in batch.windows {
                lastWindowPassed = window.passes
                guard window.passes else { continue }
                scratchUntil = now.addingTimeInterval(Self.scratchHold)
                if ignoring && !episodeOpen {
                    ignoring = false
                    changes += startEpisode(at: now, intense: false)
                }
            }
            for event in batch.events {
                switch event.kind {
                case .start:
                    if lastWindowPassed { changes += startEpisode(at: now, intense: event.intense) } else { ignoring = true }
                case .end:
                    if ignoring { ignoring = false } else { changes += endEpisode(at: now, intense: event.intense) }
                }
            }
        }

        if !live {
            // The watch's last batch after Stop. Whatever comes next is a new night.
            needsNewSession = true
            if isRunning { changes += stop(at: now) }
        }
        return changes
    }

    /// Time passing: ends the session after 8 s of silence. Call it a few times a second, and only
    /// while the phone is connected to the relay (it can't hear silence it isn't listening to).
    @discardableResult
    public mutating func tick(at now: Date) -> [Change] {
        guard isRunning, let last = lastBatchAt else { return [] }
        let since = max(last, listeningSince ?? last)
        guard now.timeIntervalSince(since) >= Self.stopAfter else { return [] }
        return stop(at: now)
    }

    /// The phone (re)connected to the relay at `now`: silence before that wasn't heard, so the 8 s
    /// stop rule counts from here. (The 60 s new-session rule still uses the last batch.)
    public mutating func resumeListening(at now: Date) {
        listeningSince = now
    }

    /// "Reset tonight's count" (hidden control) or the relay's `reset`: count 0, no episodes, and the
    /// session clock restarts (like the big-screen monitor's reset).
    public mutating func reset(at now: Date) {
        episodeOpen = false
        count = 0
        episodes = []
        scratchUntil = nil
        if startedAt != nil { startedAt = now }
    }

    // MARK: - Private

    private mutating func startEpisode(at now: Date, intense: Bool) -> [Change] {
        guard !episodeOpen else { return [] }
        episodeOpen = true
        count += 1
        episodes.append(Episode(id: count, start: now, end: nil, intense: intense))
        return [.episodeStarted(count)]
    }

    private mutating func endEpisode(at now: Date, intense: Bool) -> [Change] {
        guard episodeOpen else { return [] }
        episodeOpen = false
        guard let last = episodes.indices.last, episodes[last].end == nil else { return [] }
        episodes[last].end = now
        episodes[last].intense = episodes[last].intense || intense
        return [.episodeEnded(episodes[last].id)]
    }

    private mutating func stop(at now: Date) -> [Change] {
        var changes = endEpisode(at: now, intense: false)
        isRunning = false
        ignoring = false
        scratchUntil = nil
        changes.append(.watchStopped)
        return changes
    }
}
