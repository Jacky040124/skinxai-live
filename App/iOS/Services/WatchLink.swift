import Foundation
import WatchConnectivity
import EczemaKit

/// iPhone side of the watch link.
///
/// Contract (watch → iPhone): `WCSession.default.transferUserInfo(["kind": "episodes", "data": Data])`
/// where `data` is `JSONEncoder().encode([ScratchEpisode])`. The same payload is also accepted as a
/// message, an application context, or a transferred file whose metadata has `"kind": "episodes"`.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    enum Status: Equatable {
        case unsupported            // iPad / no WatchConnectivity
        case connecting
        case notPaired
        case paired(appInstalled: Bool)
    }

    @Published private(set) var status: Status = .connecting
    @Published private(set) var lastSync: Date?

    /// Called on the main actor with every batch of decoded episodes.
    var onEpisodes: (([ScratchEpisode]) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { status = .unsupported; return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            refresh(session)
        } else {
            session.activate()
        }
    }

    private func refresh(_ session: WCSession) {
        status = session.isPaired ? .paired(appInstalled: session.isWatchAppInstalled) : .notPaired
    }

    fileprivate func deliver(_ episodes: [ScratchEpisode]) {
        guard !episodes.isEmpty else { return }
        lastSync = Date()
        onEpisodes?(episodes)
    }

    /// Decodes the contract payload. `nil` when the payload is something else.
    nonisolated static func decode(_ payload: [String: Any]) -> [ScratchEpisode]? {
        guard payload["kind"] as? String == "episodes", let data = payload["data"] as? Data else { return nil }
        return try? JSONDecoder().decode([ScratchEpisode].self, from: data)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.status = activationState == .activated ? (paired ? .paired(appInstalled: installed) : .notPaired) : .connecting
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.status = paired ? .paired(appInstalled: installed) : .notPaired }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler(["ok": true])
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "episodes",
              let data = try? Data(contentsOf: file.fileURL),
              let episodes = try? JSONDecoder().decode([ScratchEpisode].self, from: data) else { return }
        Task { @MainActor in self.deliver(episodes) }
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        guard let episodes = WatchLink.decode(payload) else { return }
        Task { @MainActor in self.deliver(episodes) }
    }
}

/// Folds watch episodes into the day records (minutes per hour, episode and intense counts).
enum EpisodeMerge {
    /// Applies `incoming` to the dataset. An episode already present (same id) is replaced, so a
    /// later "No" from the watch (label `.rejected`) takes its minutes back out.
    /// Returns how many new, kept episodes landed in the dataset's days.
    @discardableResult
    static func apply(_ incoming: [ScratchEpisode], to d: inout TwinDataset, calendar: Calendar = .current) -> Int {
        var added = 0
        for e in incoming where e.end > e.start {
            var isNew = true
            if let i = d.episodes.firstIndex(where: { $0.id == e.id }) {
                fold(d.episodes[i], into: &d, sign: -1, calendar: calendar)
                d.episodes.remove(at: i)
                isNew = false
            }
            guard e.label != .rejected, covers(e, d, calendar) else { continue }
            fold(e, into: &d, sign: 1, calendar: calendar)
            d.episodes.append(e)
            if isNew { added += 1 }
        }
        d.episodes.sort { $0.start < $1.start }
        return added
    }

    /// Whether the episode starts on one of the dataset's days.
    static func covers(_ e: ScratchEpisode, _ d: TwinDataset, _ calendar: Calendar) -> Bool {
        d.days.contains { calendar.isDate($0.day, inSameDayAs: e.start) }
    }

    private static func fold(_ e: ScratchEpisode, into d: inout TwinDataset, sign: Double, calendar: Calendar) {
        // Minutes go to the hour(s) they happened in.
        var t = e.start
        while t < e.end {
            guard let hourStart = calendar.dateInterval(of: .hour, for: t) else { break }
            let sliceEnd = min(e.end, hourStart.end)
            let hour = calendar.component(.hour, from: t)
            if let di = d.days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: t) }), (0..<24).contains(hour) {
                let value = d.days[di].scratchMinutesByHour[hour] + sign * sliceEnd.timeIntervalSince(t) / 60
                d.days[di].scratchMinutesByHour[hour] = max(0, (value * 100).rounded() / 100)
            }
            t = sliceEnd
        }
        if let di = d.days.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: e.start) }) {
            d.days[di].episodeCount = max(0, d.days[di].episodeCount + Int(sign))
            if e.intense { d.days[di].intenseCount = max(0, d.days[di].intenseCount + Int(sign)) }
        }
    }
}
