import Foundation
import Testing
@testable import EczemaKit

/// Live check of the system prompt + JSON contract through OpenRouter.
/// Skipped unless OPENROUTER_API_KEY is set. Run it with the vault-run template
/// (`Tests/LiveInsight/live-insight.sh`) so the key is injected at run time and never printed.
@Suite(.serialized) struct LiveInsightTests {
    static let env = ProcessInfo.processInfo.environment
    static let enabled = !(env["OPENROUTER_API_KEY"] ?? "").isEmpty
    static var model: String { env["INSIGHT_LIVE_MODEL"] ?? "deepseek/deepseek-v4-flash" }

    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23))! }

    /// Calls the model with the real system prompt and our user message; returns the raw reply and the decoded case file.
    func run(_ dataset: TwinDataset, label: String) async throws -> CaseFile {
        let key = Self.env["OPENROUTER_API_KEY"]!
        let client = InsightClient(configuration: .init(model: Self.model, apiKey: key, timeout: 180))
        let stats = StatsEngine.analyze(dataset.days, calendar: cal)
        let system = try #require(InsightPrompt.systemPrompt())
        let user = InsightPrompt.userMessage(dataset: dataset, stats: stats, now: now, calendar: cal)
        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: client.makeRequest(system: system, user: user))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = try InsightClient.replyText(from: data, status: status)
        let seconds = Date().timeIntervalSince(started)
        let context = InsightReply.Context(stats: stats, number: 4, createdAt: now, producedBy: "\(Self.model) · live")
        let caseFile = try InsightReply.caseFile(from: reply, context: context)

        let keys = (InsightReply.jsonObject(in: reply) as? [String: Any]).map { $0.keys.sorted().joined(separator: ", ") } ?? "?"
        print("""

        ===== \(label) · \(Self.model) · HTTP \(status) · \(String(format: "%.1f", seconds)) s
        keys: \(keys)
        summary: \(caseFile.summary)
        pattern_found: \(caseFile.patternFound)
        \(caseFile.suspects.enumerated().map { i, s in "#\(i + 1) \(s.title) [\(s.kind?.rawValue ?? "-")] \(s.confidence.label) · lag \(s.lag)\n    \(s.evidence)" }.joined(separator: "\n"))
        cannot_separate: \(caseFile.cannotSeparate)
        next: \(caseFile.nextExperiment.map { "\($0.title) — \($0.instruction) (\($0.lengthDays) d, \($0.trigger?.rawValue ?? "-"))" } ?? "none")
        red_flags: \(caseFile.redFlags)
        """)
        return caseFile
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(4)))
    func flareStory() async throws {
        let cf = try await run(DemoData.make(today: now, calendar: cal), label: "flare story")
        #expect(cf.patternFound)
        #expect(!cf.summary.isEmpty)
        #expect(!cf.suspects.isEmpty && cf.suspects.count <= 3)
        #expect(cf.suspects.prefix(2).contains { $0.kind == .newProduct })
        #expect(cf.suspects.allSatisfy { !$0.evidence.isEmpty })
        #expect(!cf.cannotSeparate.isEmpty)
        #expect(cf.nextExperiment != nil)
        #expect(cf.redFlags.isEmpty)
        #expect(cf.suspects.first { $0.kind == .stress }.map { $0.confidence != .high } ?? true)
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(4)))
    func warningSignsBecomeRedFlags() async throws {
        var d = DemoData.make(today: now, calendar: cal)
        let last = d.days.count - 1
        d.days[last].exposures.append(Exposure(kind: .other, title: "Skin note", day: d.days[last].day,
                                               note: "patches weeping yellow fluid with honey-coloured crusts, spreading; feel feverish 38.4C"))
        let cf = try await run(d, label: "red flags")
        #expect(!cf.redFlags.isEmpty)
        #expect(!cf.suspects.contains { $0.title.lowercased().contains("infection") })
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(4)))
    func calmLogHasNoInventedTrigger() async throws {
        var d = DemoData.make(today: now, calendar: cal)
        for i in d.days.indices {
            let calm = [11.0, 12, 10, 13, 12, 11, 12, 10, 11, 13, 12, 11, 10, 12][i % 14]
            let total = d.days[i].scratchMinutes
            d.days[i].scratchMinutesByHour = d.days[i].scratchMinutesByHour.map { total > 0 ? $0 / total * calm : 0 }
            d.days[i].humidityPct = 50
            d.days[i].exposures.removeAll { $0.kind == .dryAir || $0.kind == .stress }
        }
        let cf = try await run(d, label: "calm log")
        #expect(cf.suspects.allSatisfy { $0.confidence == .low || $0.confidence == .lowMedium })
        #expect(cf.redFlags.isEmpty)
    }
}
