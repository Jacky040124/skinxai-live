import Foundation
import Combine
import SwiftUI
import UIKit
import EczemaKit

/// One scratching episode the watch reported tonight.
struct LiveEpisode: Identifiable, Equatable {
    /// 1, 2, 3 … in the order the episodes started tonight.
    let id: Int
    let start: Date
    /// When it ended; nil while it is still going on.
    var end: Date?
}

/// What the watch is doing right now, as the phone hears it through the live relay
/// (`wss://eczema-twin-live.zhongzhenyu190.workers.dev/api/live`).
///
/// The rules are EczemaKit's `LiveRelayState` (a port of the big-screen monitor's `take()` plus the
/// stage session rules); this object feeds it from the relay socket — or from the built-in stand-in
/// watch with `-liveSim 1` — ticks it, and publishes the result for the pill and the monitor.
/// It lives from launch (`EczemaTwinApp.init`) and listens while the app is active.
///
/// When the watch stops (a `live: false` batch, or 8 s without batches) an open monitor closes
/// itself (`LiveMonitorPresenter.watchDidStop()`); a closed one just loses its pill.
@MainActor
final class LiveSession: ObservableObject {
    static let shared = LiveSession()

    /// The watch is tracking sleep: a batch arrived in the last 3.5 s and it wasn't `live: false`.
    @Published private(set) var tracking = false
    /// A scratch is going on right now.
    @Published private(set) var scratching = false
    /// Scratches tonight: episodes started in this tracking session.
    @Published private(set) var count = 0
    /// When this tracking session began.
    @Published private(set) var startedAt: Date?
    /// Tonight's episodes, oldest first.
    @Published private(set) var episodes: [LiveEpisode] = []
    /// A session runs from its first batch until the watch stops. Unlike `tracking` it rides out a
    /// few seconds without batches, so the monitor's bars don't flatten on a network hiccup.
    @Published private(set) var running = false

    private var rules = LiveRelayState()
    private let relay: LiveRelayClient?
    private let simulator: LiveSimulator?
    /// The phone can hear the watch right now (socket up, or the stand-in running).
    private var listening = false
    /// When the phone stopped hearing the relay (socket down, app in the background).
    private var deafSince: Date?
    private var ticker: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    private init() {
        let defaults = UserDefaults.standard
        if let sim = defaults.string(forKey: "liveSim"), !["", "0", "NO", "no", "false"].contains(sim) {
            let stop = defaults.double(forKey: "liveSimStop")
            simulator = LiveSimulator(stopAfter: stop > 0 ? stop : nil)
            relay = nil
        } else {
            simulator = nil
            relay = LiveRelayClient()
        }
        relay?.onMessage = { [weak self] message in self?.receive(message) }
        relay?.onConnect = { [weak self] in self?.startedListening() }
        relay?.onDisconnect = { [weak self] in self?.stoppedListening() }
        simulator?.onBatch = { [weak self] batch in self?.receive(.batch(batch)) }

        let center = NotificationCenter.default
        // Hidden control "Reset tonight's count".
        center.publisher(for: .twinResetTonight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &bag)
        // Listen while the app is active (the socket closes in the background).
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.appBecameActive() }
            .store(in: &bag)
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relay?.stop() }
            .store(in: &bag)

        // `-screen live` opens the monitor at launch (after this object exists: the presenter reads it).
        if defaults.string(forKey: "screen") == "live" {
            let waitForTracking = simulator != nil
            DispatchQueue.main.async {
                LiveMonitorPresenter.shared.openWhenReady(waitForTracking: waitForTracking)
            }
        }
        #if DEBUG
        DispatchQueue.main.async { LivePillHarness.presentIfRequested() }
        #endif
    }

    /// Sets tonight's count back to zero (the hidden control, or the relay's `reset` message).
    func reset() {
        rules.reset(at: Date())
        publish()
    }

    // MARK: - Input

    private func appBecameActive() {
        relay?.start()
        if let simulator {
            simulator.start()
            if !listening { startedListening() }
        }
    }

    private func startedListening() {
        let now = Date()
        if let deafSince { rules.notListening(from: deafSince, to: now) }
        deafSince = nil
        listening = true
    }

    private func stoppedListening() {
        listening = false
        deafSince = Date()
    }

    private func receive(_ message: LiveRelayMessage) {
        let now = Date()
        switch message {
        case .batch(let batch):
            let changes = rules.take(batch, at: now)
            publish(now)
            if changes.contains(.watchStopped) { watchStopped() }
            startTicking()
        case .reset:
            rules.reset(at: now)
            publish(now)
        case .other:
            break
        }
    }

    // MARK: - Time

    /// Ten times a second while anything can still change with time (the 1.2 s scratch hold,
    /// tracking's 3.5 s, the 8 s stop); idle otherwise.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                if !self.tick() {
                    self.ticker = nil
                    return
                }
            }
        }
    }

    /// Returns false when nothing is left to change.
    private func tick() -> Bool {
        let now = Date()
        // Silence only counts while the phone can hear the relay.
        let changes = listening ? rules.tick(at: now) : []
        publish(now)
        if changes.contains(.watchStopped) { watchStopped() }
        return rules.isRunning || tracking || scratching
    }

    private func watchStopped() {
        LiveMonitorPresenter.shared.watchDidStop()
    }

    /// Copies the rules' state into the published properties (only what changed, so views redraw
    /// only when something did). The pill comes and goes with a spring.
    private func publish(_ now: Date = Date()) {
        let isTracking = rules.isTracking(at: now)
        if isTracking != tracking {
            withAnimation(isTracking ? Twin.Motion.bouncy : Twin.Motion.slide) { tracking = isTracking }
        }
        let isScratching = rules.isScratching(at: now)
        if isScratching != scratching { scratching = isScratching }
        if rules.count != count { count = rules.count }
        if rules.startedAt != startedAt { startedAt = rules.startedAt }
        if rules.isRunning != running { running = rules.isRunning }
        let list = rules.episodes.map { LiveEpisode(id: $0.id, start: $0.start, end: $0.end) }
        if list != episodes { episodes = list }
    }
}
