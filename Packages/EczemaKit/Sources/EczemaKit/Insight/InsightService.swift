import Foundation

/// The result of an analysis run: the case file to show and where it came from.
public struct InsightOutcome: Sendable {
    public enum Source: Equatable, Sendable {
        /// The model answered (OpenRouter model id).
        case live(model: String)
        /// The bundled analysis was used instead.
        case bundled(BundledReason)
    }

    public enum BundledReason: String, Equatable, Sendable {
        case noKey, offline, failed
        /// The model took longer than the caller's time limit.
        case slow
        /// The provider refused the API key (HTTP 401 / 403).
        case badKey
        /// The provider account has no credits left (HTTP 402).
        case noCredits

        /// Small print for the UI.
        public var note: String {
            switch self {
            case .noKey: "Bundled analysis"
            case .offline: "Bundled analysis · offline"
            case .failed: "Bundled analysis · model unavailable"
            case .slow: "Bundled analysis · model slow"
            case .badKey: "Bundled analysis · key not accepted"
            case .noCredits: "Bundled analysis · no credits left"
            }
        }
    }

    public var caseFile: CaseFile
    public var source: Source
    public var stats: InsightStats

    public init(caseFile: CaseFile, source: Source, stats: InsightStats) {
        self.caseFile = caseFile; self.source = source; self.stats = stats
    }

    public var isLive: Bool { if case .live = source { return true } else { return false } }
    /// Why the bundled analysis was used, nil for a live answer.
    public var bundledReason: BundledReason? { if case .bundled(let r) = source { return r } else { return nil } }
}

/// Stats first, then the model explains — with the bundled analysis whenever there is no key,
/// no network or any error. The demo never depends on the network.
public enum InsightService {

    /// Runs the full analysis. Never throws: falls back to the bundled case file.
    /// - Parameter limit: hard limit in seconds for the live call (nil = the request's own timeout). When the
    ///   model takes longer, the call is cancelled and the bundled analysis comes back with reason `.slow`.
    public static func analyze(dataset: TwinDataset, apiKey: String?, model: String, now: Date = Date(),
                               calendar: Calendar = .current, session: URLSession = .shared,
                               limit: TimeInterval? = nil) async -> InsightOutcome {
        let stats = StatsEngine.analyze(dataset.days, calendar: calendar)
        let bundled = bundledCaseFile(for: dataset, calendar: calendar)
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return InsightOutcome(caseFile: bundled, source: .bundled(.noKey), stats: stats)
        }
        let client = InsightClient(configuration: .init(model: model, apiKey: key), session: session)
        let number = (dataset.caseFile?.number ?? 0) + 1
        let call: @Sendable () async -> InsightOutcome = {
            do {
                let live = try await client.analyze(dataset: dataset, stats: stats, number: number, now: now, calendar: calendar)
                return InsightOutcome(caseFile: live, source: .live(model: model), stats: stats)
            } catch InsightClient.Failure.offline {
                return InsightOutcome(caseFile: bundled, source: .bundled(.offline), stats: stats)
            } catch InsightClient.Failure.http(let code, _) where code == 401 || code == 403 {
                return InsightOutcome(caseFile: bundled, source: .bundled(.badKey), stats: stats)
            } catch InsightClient.Failure.http(402, _) {
                return InsightOutcome(caseFile: bundled, source: .bundled(.noCredits), stats: stats)
            } catch {
                return InsightOutcome(caseFile: bundled, source: .bundled(.failed), stats: stats)
            }
        }
        guard let limit else { return await call() }
        return await withTimeLimit(limit, call) ?? InsightOutcome(caseFile: bundled, source: .bundled(.slow), stats: stats)
    }

    /// Runs `operation`, or gives up after `seconds` (the operation is cancelled) and returns nil.
    public static func withTimeLimit<T: Sendable>(_ seconds: TimeInterval,
                                                  _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The bundled analysis for this dataset (`DemoData.demoCaseFile`, dated to match the data).
    public static func bundledCaseFile(for dataset: TwinDataset, calendar: Calendar = .current) -> CaseFile {
        if let current = dataset.caseFile, current.isBundled { return current }
        let days = dataset.days.map(\.day)
        let today = calendar.startOfDay(for: Date())
        func day(_ i: Int) -> Date { days.isEmpty ? today : days[min(max(i, 0), days.count - 1)] }
        func first(_ kind: ExposureKind) -> Date? { dataset.days.first { d in d.exposures.contains { $0.kind == kind } }?.day }
        let stats = StatsEngine.analyze(dataset.days, calendar: calendar)
        let storyEnd = min(DemoData.flareMinutes.count - 1, max(days.count - 1, 0))
        let caseFile = DemoData.demoCaseFile(
            created: day(storyEnd), windowStart: day(0),
            washDay: first(.newProduct) ?? day(DemoData.bodyWashDay),
            dryDay: first(.dryAir) ?? day(DemoData.dryAirDay),
            flareDay: stats.flares.first?.start ?? day(DemoData.flareStartDay),
            examDay: first(.stress) ?? day(DemoData.examDays.min() ?? 10))
        return caseFile
    }

    /// Number of days a case file covers (inclusive).
    public static func windowDays(_ caseFile: CaseFile, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: caseFile.windowStart), b = calendar.startOfDay(for: caseFile.windowEnd)
        return (calendar.dateComponents([.day], from: a, to: b).day ?? 13) + 1
    }
}

extension CaseFile {
    /// True for the analysis that ships with the app (`DemoData.demoCaseFile`), false for a live model's.
    public var isBundled: Bool { producedBy.localizedCaseInsensitiveContains("bundled") }

    /// The model that wrote a live case file ("claude-sonnet-5.5" from "claude-sonnet-5.5 · live"); nil when bundled.
    public var liveModel: String? {
        guard !isBundled else { return nil }
        let name = producedBy.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }
}
