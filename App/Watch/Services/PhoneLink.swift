import Foundation
import WatchConnectivity
import EczemaKit

/// What the iPhone shows, so the watch shows the same (Settings → Demo story, demo time travel).
///
/// Contract (iPhone → watch): `WCSession.default.updateApplicationContext(["dataMode": "demo"|"real",
/// "expDay": n])`, sent whenever either changes. `expDay` 1...10 is the day of the 10-day test;
/// missing or 0 means the flare story. Optional extras the watch also follows:
/// `"storyDay": 1...14`, the day of the flare story shown as today (14, the default, is the day the
/// case file is ready), and `"storyAt": <seconds since 1970>`, when the iPhone built its story (the
/// demo's "today so far" ends at that hour; without it the watch builds the story at the current hour).
struct PhoneContext: Equatable, Sendable {
    enum Mode: String, Sendable { case demo, real }

    var mode: Mode
    var expDay: Int?
    var storyDay: Int?
    var storyAt: Date?

    static let demo = PhoneContext(mode: .demo, expDay: nil, storyDay: nil, storyAt: nil)

    init(mode: Mode, expDay: Int?, storyDay: Int?, storyAt: Date?) {
        let testLength = DemoData.experimentMinutes.count, storyLength = DemoData.flareMinutes.count
        self.mode = mode
        self.expDay = mode == .demo ? expDay.flatMap { $0 >= 1 ? min($0, testLength) : nil } : nil
        let story = mode == .demo && self.expDay == nil ? storyDay.flatMap { $0 >= 1 ? min($0, storyLength) : nil } : nil
        self.storyDay = story == storyLength ? nil : story
        self.storyAt = mode == .demo ? storyAt : nil
    }

    /// nil when the dictionary has no (valid) `dataMode`.
    init?(_ dict: [String: Any]) {
        guard let raw = dict["dataMode"] as? String, let mode = Mode(rawValue: raw.lowercased()) else { return nil }
        let at: Date? = switch dict["storyAt"] {
        case let d as Date: d
        case let n as NSNumber: Date(timeIntervalSince1970: n.doubleValue)
        default: nil
        }
        self.init(mode: mode, expDay: Self.int(dict["expDay"]), storyDay: Self.int(dict["storyDay"]), storyAt: at)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["dataMode": mode.rawValue]
        if let expDay { d["expDay"] = expDay }
        if let storyDay { d["storyDay"] = storyDay }
        if let storyAt { d["storyAt"] = storyAt.timeIntervalSince1970 }
        return d
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s)
        default: nil
        }
    }
}

/// Sends the watch's episodes to the iPhone and hears which data the iPhone shows.
///
/// Contract (watch → iPhone): `WCSession.default.transferUserInfo(["kind": "episodes",
/// "data": <Data>])` where `<Data>` is `JSONEncoder().encode([ScratchEpisode])` with default settings.
/// transferUserInfo is queued by the system and delivered even if the phone is away right now.
/// Real episodes have source `.live`/`.recorded`; confirmed demo-story ones (the long-press alert,
/// the simulator's scripted wrist) have source `.demo` and are only sent to an iPhone that told us
/// its data mode, so they always land in its demo overlay and never in its real data.
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    /// Called on the main actor when a transfer failed, with the ids to send again later.
    var onFailed: (@MainActor ([UUID]) -> Void)?
    /// Called on the main actor once the session is active (time to send what's waiting).
    var onActivated: (@MainActor () -> Void)?
    /// Called on the main actor with the iPhone's latest data mode.
    var onContext: (@MainActor (PhoneContext) -> Void)?

    private var activated = false
    /// The latest data mode heard from the iPhone (kept for a model that starts listening late).
    @MainActor private(set) var lastContext: PhoneContext?

    var isAvailable: Bool { WCSession.isSupported() }
    var isActivated: Bool { activated }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() } else { activated = true }
    }

    /// Hands the episodes to WatchConnectivity (in batches of 200, so a long offline stretch never
    /// becomes one huge transfer). Returns false when it could not (yet).
    @discardableResult
    func send(_ episodes: [ScratchEpisode]) -> Bool {
        guard !episodes.isEmpty, WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { activate(); return false }
        let encoder = JSONEncoder()
        var start = 0
        while start < episodes.count {
            let batch = Array(episodes[start..<min(episodes.count, start + 200)])
            guard let data = try? encoder.encode(batch) else { return false }
            session.transferUserInfo(["kind": "episodes", "data": data])
            start += 200
        }
        return true
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ok = activationState == .activated
        // The last context the phone sent is kept by the system: pick it up at every launch.
        let context = ok ? PhoneContext(session.receivedApplicationContext) : nil
        Task { @MainActor in
            self.activated = ok
            if let context { self.heard(context) }
            if ok { self.onActivated?() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = PhoneContext(applicationContext) else { return }
        Task { @MainActor in self.heard(context) }
    }

    @MainActor private func heard(_ context: PhoneContext) {
        lastContext = context
        onContext?(context)
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil,
              userInfoTransfer.userInfo["kind"] as? String == "episodes",
              let data = userInfoTransfer.userInfo["data"] as? Data,
              let episodes = try? JSONDecoder().decode([ScratchEpisode].self, from: data) else { return }
        let ids = episodes.filter { $0.source != .demo }.map(\.id)
        guard !ids.isEmpty else { return }
        Task { @MainActor in self.onFailed?(ids) }
    }
}
