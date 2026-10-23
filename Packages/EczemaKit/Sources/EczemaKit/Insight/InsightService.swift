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

        /// Small print for the UI.
        public var note: String {
            switch self {
            case .noKey: "Bundled analysis"
            case .offline: "Bundled analysis · offline"
            case .failed: "Bundled analysis · model unavailable"
            }
        }
    }

    public var caseFile: CaseFile
    public var source: Source
    public var stats: InsightStats

    public var isLive: Bool { if case .live = source { return true } else { return false } }
}

/// Stats first, then the model explains — with the bundled analysis whenever there is no key,
/// no network or any error. The demo never depends on the network.
public enum InsightService {

    /// Runs the full analysis. Never throws: falls back to the bundled case file.
    public static func analyze(dataset: TwinDataset, apiKey: String?, model: String, now: Date = Date(),
                               calendar: Calendar = .current, session: URLSession = .shared) async -> InsightOutcome {
        let stats = StatsEngine.analyze(dataset.days, calendar: calendar)
        let bundled = bundledCaseFile(for: dataset, calendar: calendar)
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return InsightOutcome(caseFile: bundled, source: .bundled(.noKey), stats: stats)
        }
        let client = InsightClient(configuration: .init(model: model, apiKey: key), session: session)
        do {
            let number = (dataset.caseFile?.number ?? 0) + 1
            let live = try await client.analyze(dataset: dataset, stats: stats, number: number, now: now, calendar: calendar)
            return InsightOutcome(caseFile: live, source: .live(model: model), stats: stats)
        } catch InsightClient.Failure.offline {
            return InsightOutcome(caseFile: bundled, source: .bundled(.offline), stats: stats)
        } catch {
            return InsightOutcome(caseFile: bundled, source: .bundled(.failed), stats: stats)
        }
    }

    /// The bundled analysis for this dataset (`DemoData.demoCaseFile`, dated to match the data).
    public static func bundledCaseFile(for dataset: TwinDataset, calendar: Calendar = .current) -> CaseFile {
        if let current = dataset.caseFile, current.producedBy.localizedCaseInsensitiveContains("bundled") { return current }
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
