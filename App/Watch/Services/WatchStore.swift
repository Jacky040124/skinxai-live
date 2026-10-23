import Foundation
import EczemaKit

/// Local persistence on the watch: real episodes (`episodes.json`), the personal model
/// (`model.json`) and bookkeeping (`state.json`), all in Application Support.
/// Demo and simulated episodes are never written here.
@MainActor
final class WatchStore {
    struct Bookkeeping: Codable {
        /// Episodes already handed to WatchConnectivity.
        var sentIDs: Set<UUID> = []
        /// Recorded accelerometer data is analysed up to here.
        var analyzedThrough: Date?
        /// The current CMSensorRecorder recording runs until here.
        var recorderArmedUntil: Date?
        /// Window features of recent episodes, so a late answer can still teach the model.
        var evidence: [String: [WindowFeatures]] = [:]
        var lastSentAt: Date?
    }

    private(set) var episodes: [ScratchEpisode] = []
    private(set) var model = ScratchModel()
    private(set) var book = Bookkeeping()

    /// Keep two weeks of episodes on the watch.
    private let retention: TimeInterval = 14 * 86_400
    private let dir: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("EczemaTwin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        episodes = read([ScratchEpisode].self, "episodes.json") ?? []
        model = read(ScratchModel.self, "model.json") ?? ScratchModel()
        book = read(Bookkeeping.self, "state.json") ?? Bookkeeping()
        prune()
    }

    // MARK: - Episodes

    /// Adds real episodes, skipping any that overlap one we already have (live and recorded data
    /// can cover the same minutes). Returns the ones actually added.
    @discardableResult
    func add(_ new: [ScratchEpisode]) -> [ScratchEpisode] {
        var added: [ScratchEpisode] = []
        for e in new where e.source != .demo {
            let overlaps = episodes.contains { $0.id == e.id || ($0.start < e.end && e.start < $0.end) }
            if !overlaps { episodes.append(e); added.append(e) }
        }
        if !added.isEmpty {
            episodes.sort { $0.start < $1.start }
            write(episodes, "episodes.json")
        }
        return added
    }

    func episode(_ id: UUID) -> ScratchEpisode? { episodes.first { $0.id == id } }

    func setLabel(_ label: EpisodeLabel, for id: UUID) {
        guard let i = episodes.firstIndex(where: { $0.id == id }) else { return }
        episodes[i].label = label
        write(episodes, "episodes.json")
    }

    /// Real episodes that still have to go to the iPhone (rejected ones never go).
    func unsent(excluding id: UUID? = nil) -> [ScratchEpisode] {
        episodes.filter { $0.label != .rejected && !book.sentIDs.contains($0.id) && $0.id != id }
    }

    func markSent(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        book.sentIDs.formUnion(ids)
        book.lastSentAt = Date()
        saveBook()
    }

    func markUnsent(_ ids: [UUID]) {
        book.sentIDs.subtract(ids)
        saveBook()
    }

    // MARK: - Model and evidence

    func setModel(_ m: ScratchModel) {
        model = m
        write(m, "model.json")
    }

    func setEvidence(_ windows: [WindowFeatures], for id: UUID) {
        book.evidence[id.uuidString] = windows
        if book.evidence.count > 40 {
            // Forget the oldest evidence.
            let keep = Set(episodes.suffix(40).map(\.id.uuidString))
            book.evidence = book.evidence.filter { keep.contains($0.key) || $0.key == id.uuidString }
        }
        saveBook()
    }

    func evidence(for id: UUID) -> [WindowFeatures]? { book.evidence[id.uuidString] }

    // MARK: - Recorder bookkeeping

    func setAnalyzedThrough(_ date: Date) {
        book.analyzedThrough = date
        saveBook()
    }

    func setRecorderArmedUntil(_ date: Date) {
        book.recorderArmedUntil = date
        saveBook()
    }

    // MARK: - Files

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        let kept = episodes.filter { $0.end >= cutoff }
        if kept.count != episodes.count {
            let dropped = Set(episodes.map(\.id)).subtracting(kept.map(\.id))
            episodes = kept
            book.sentIDs.subtract(dropped)
            write(episodes, "episodes.json")
            saveBook()
        }
    }

    private func saveBook() { write(book, "state.json") }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: [.atomic])
    }
}
