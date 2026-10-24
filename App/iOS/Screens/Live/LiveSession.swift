import Foundation
import Combine

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
/// Foundation stub with the final API: nothing is connected yet, so `tracking` stays false and the
/// pill never shows. The `live` area connects it (STAGE-SPEC §4).
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

    private var bag = Set<AnyCancellable>()

    private init() {
        // Hidden control "Reset tonight's count".
        NotificationCenter.default.publisher(for: .twinResetTonight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &bag)
    }

    /// Sets tonight's count back to zero (the hidden control, or the relay's `reset` message).
    func reset() {
        count = 0
        episodes = []
        scratching = false
    }
}
