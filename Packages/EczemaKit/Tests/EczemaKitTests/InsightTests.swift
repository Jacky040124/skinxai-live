import Foundation
import Testing
@testable import EczemaKit

private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
private let now: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23))!

private func day(_ offset: Int, from start: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!) -> Date {
    cal.date(byAdding: .day, value: offset, to: start)!
}

/// A plain day with `minutes` of scratching and the given exposures.
private func record(_ i: Int, _ minutes: Double, _ exposures: [(ExposureKind, String)] = []) -> DayRecord {
    var hourly = [Double](repeating: 0, count: 24)
    hourly[3] = minutes
    return DayRecord(day: day(i), scratchMinutesByHour: hourly, episodeCount: Int(minutes / 2), intenseCount: 0, sleepHours: 7,
                     wakeUps: 1, hrvMs: 48, restingHR: 58, humidityPct: 50, tempC: 15, aqi: 30, pollen: .low,
                     exposures: exposures.map { Exposure(kind: $0.0, title: $0.1, day: day(i)) })
}

// MARK: - StatsEngine

@Suite struct StatsEngineTests {
    let demo = DemoData.make(today: now, calendar: cal)

    @Test func baselineIsMedianOfCalmDays() {
        let stats = StatsEngine.analyze(demo.days, calendar: cal)
        #expect(abs(stats.baselineMinutes - demo.baselineMinutesPerDay) < 0.6)
        #expect(abs(stats.thresholdMinutes - stats.baselineMinutes * 1.5) < 0.01)
        #expect(StatsEngine.baseline([]) == 0)
        #expect(StatsEngine.baseline([5, 5, 5]) == 5)
        // Robust to a long flare: more than half the days high.
        #expect(abs(StatsEngine.baseline([10, 11, 12, 30, 32, 35, 40, 41, 44]) - 11) < 0.01)
    }

    @Test func flareStartsOnDaySeven() throws {
        let stats = StatsEngine.analyze(demo.days, calendar: cal)
        #expect(stats.flares.count == 1)
        let flare = try #require(stats.currentFlare)
        #expect(flare.startIndex == DemoData.flareStartDay)
        #expect(flare.endIndex == demo.days.count - 1)
        #expect(cal.isDate(flare.start, inSameDayAs: demo.days[DemoData.flareStartDay].day))
        #expect(abs(flare.peakMinutes - 47) < 1.5)
    }

    @Test func anomalyNeedsTwoDaysInARow() {
        #expect(StatsEngine.flareRuns([10, 10, 30, 10, 10], threshold: 15).isEmpty)
        #expect(StatsEngine.flareRuns([10, 30, 31, 10, 30], threshold: 15) == [1...2])
        #expect(StatsEngine.flareRuns([10, 10, 30, 31], threshold: 15) == [2...3])
        #expect(StatsEngine.threshold(baseline: 0) == 2)    // tiny baselines need a real jump
    }

    @Test func laggedEffectAndOnsets() throws {
        let stats = StatsEngine.analyze(demo.days, calendar: cal)
        let wash = try #require(stats.exposure(kind: .newProduct))
        let dry = try #require(stats.exposure(kind: .dryAir))
        let exam = try #require(stats.exposure(kind: .stress))
        let gym = try #require(stats.exposure(kind: .sweat))
        let dairy = try #require(stats.exposure(kind: .dairy))

        #expect(wash.onset == .beforeFlare && wash.leadDays == 2)
        #expect(dry.onset == .beforeFlare && dry.leadDays == 1)
        #expect(exam.onset == .afterFlareStart)
        #expect((wash.effectRatio ?? 0) > 2.2)
        #expect((dry.effectRatio ?? 0) > 2.2)
        #expect(wash.bestLag == 2)
        #expect(dry.bestLag == 1)
        // Workouts and dairy come and go with no effect.
        #expect(abs((gym.effectRatio ?? 9) - 1) < 0.2)
        #expect(abs((dairy.effectRatio ?? 9) - 1) < 0.2)
        // Ranked: the two candidates first, exam stress (started after the flare) below them.
        let order = stats.exposures.map(\.kind)
        #expect(Set(order.prefix(2)) == [.newProduct, .dryAir])
        #expect(order.firstIndex(of: .stress)! > 1)
        #expect(wash.presentOnLastDay && dry.presentOnLastDay)
    }

    @Test func bodyWashAndDryAirCannotBeSeparated() throws {
        let stats = StatsEngine.analyze(demo.days, calendar: cal)
        #expect(stats.cannotSeparate.count == 1)
        let group = try #require(stats.cannotSeparate.first)
        let kinds = Set(group.compactMap { stats.exposure(id: $0)?.kind })
        #expect(kinds == [.newProduct, .dryAir])
        let wash = try #require(stats.exposure(kind: .newProduct))
        #expect(stats.confounded(with: wash.id).count == 1)
    }

    @Test func pausingTheWashSeparatesThem() throws {
        let done = DemoData.make(today: now, experimentDay: 10, calendar: cal)
        let stats = StatsEngine.analyze(done.days, calendar: cal)
        #expect(stats.cannotSeparate.isEmpty)
        let wash = try #require(stats.exposure(kind: .newProduct))
        let dry = try #require(stats.exposure(kind: .dryAir))
        #expect((wash.effectRatio ?? 0) > (dry.effectRatio ?? 0))
    }

    @Test func calmLogHasNoFlareAndNoSuspects() {
        let minutes: [Double] = [11, 12, 10, 13, 12, 11, 12, 10, 11, 13, 12, 11, 10, 12]
        let days = minutes.enumerated().map { i, m in record(i, m, i % 3 == 0 ? [(.dairy, "Dairy")] : []) }
        let stats = StatsEngine.analyze(days, calendar: cal)
        #expect(stats.flares.isEmpty)
        #expect(stats.exposures.allSatisfy { $0.onset == .noFlare })
        #expect(stats.cannotSeparate.isEmpty)
    }

    @Test func sameDayStartsAreConfounded() {
        // A new product and dry air start together on day 6; flare from day 7.
        let minutes: [Double] = [10, 11, 10, 12, 11, 10, 11, 30, 32, 35, 31, 33, 34, 36]
        let days = minutes.enumerated().map { i, m in
            record(i, m, i >= 6 ? [(.newProduct, "New lotion"), (.dryAir, "Dry air")] : [])
        }
        let stats = StatsEngine.analyze(days, calendar: cal)
        #expect(stats.cannotSeparate.count == 1)
        #expect(stats.cannotSeparate.first?.count == 2)
    }
}

// MARK: - Prompt

@Suite struct InsightPromptTests {
    @Test func systemPromptIsBundled() throws {
        let system = try #require(InsightPrompt.systemPrompt())
        #expect(system.contains("JSON only"))
        #expect(system.contains("plain_summary"))
        #expect(system.contains("red_flags"))
        #expect(system.contains("dryAir"))
    }

    @Test func userMessageHasStatsAndLog() {
        let demo = DemoData.make(today: now, calendar: cal)
        let stats = StatsEngine.analyze(demo.days, calendar: cal)
        let text = InsightPrompt.userMessage(dataset: demo, stats: stats, now: now, calendar: cal)
        #expect(text.contains("Usual scratching (median of calm days): 11.5 min/day"))
        #expect(text.contains("New scented body wash [kind newProduct, tagged by them]"))
        #expect(text.contains("started 2 days before the flare began"))
        #expect(text.contains("Cannot separate yet: "))
        #expect(text.contains("(today, partial)"))
        let logRows = text.components(separatedBy: "\n").filter { $0.contains(" | ") }
        #expect(logRows.count == demo.days.count + 1)      // header + one row per day
        #expect(!text.contains("Running test"))

        let exp = DemoData.make(today: now, experimentDay: 6, calendar: cal)
        let expText = InsightPrompt.userMessage(dataset: exp, stats: StatsEngine.analyze(exp.days, calendar: cal), now: now, calendar: cal)
        #expect(expText.contains("Running test: \"Pause the body wash\""))
        #expect(expText.contains("(day 6 of 10)"))
    }
}

// MARK: - Reply decoding

@Suite struct InsightReplyTests {
    let demo = DemoData.make(today: now, calendar: cal)
    var stats: InsightStats { StatsEngine.analyze(demo.days, calendar: cal) }
    var context: InsightReply.Context { .init(stats: stats, number: 4, createdAt: now, producedBy: "test · live") }

    static let clean = """
    {"pattern_found": true,
     "plain_summary": "Your scratching nearly tripled from Oct 18. The new scented body wash is the most likely cause.",
     "suspects": [
       {"trigger": "New scented body wash", "kind": "newProduct", "confidence": "medium", "lag_days": "about 2",
        "evidence": "Scratching rose 2 days after you started it."},
       {"trigger": "Dry air", "kind": "dryAir", "confidence": "low-medium", "lag_days": "0-1", "evidence": "Humidity fell below 30%."},
       {"trigger": "Exam stress", "kind": "stress", "confidence": "low", "lag_days": "0-1", "evidence": "Came after the flare started."}
     ],
     "cannot_separate": ["The body wash and the dry air started one day apart."],
     "next_experiment": {"title": "Pause the body wash", "instruction": "Use your old wash for 10 days.", "kind": "newProduct", "length_days": 10},
     "red_flags": []}
    """

    @Test func decodesTheContract() throws {
        let cf = try InsightReply.caseFile(from: Self.clean, context: context)
        #expect(cf.number == 4 && cf.producedBy == "test · live")
        #expect(cf.patternFound)
        #expect(cf.suspects.map(\.kind) == [.newProduct, .dryAir, .stress])
        #expect(cf.suspects.map(\.confidence) == [.medium, .lowMedium, .low])
        #expect(cf.suspects[0].lag == "about 2 days")
        #expect(cf.suspects[1].lag == "0–1 day")
        let wash = try #require(stats.exposure(kind: .newProduct))
        #expect(cf.suspects[0].startedOn == wash.firstDay)
        #expect(cf.suspects[0].flareOn == stats.currentFlare?.start)
        #expect(cf.suspects[2].flareOn == nil)                 // started after the flare: no arc to the flare
        #expect(cf.nextExperiment?.title == "Pause the body wash")
        #expect(cf.nextExperiment?.trigger == .newProduct)
        #expect(cf.nextExperiment?.lengthDays == 10)
        #expect(cf.cannotSeparate.count == 1 && cf.redFlags.isEmpty)
        #expect(cf.windowStart == stats.windowStart && cf.windowEnd == stats.windowEnd)
    }

    @Test func survivesFencesChatterAndThinking() throws {
        let fenced = "Sure! Here is the analysis:\n```json\n\(Self.clean)\n```\nLet me know if you need more."
        #expect(try InsightReply.caseFile(from: fenced, context: context).suspects.count == 3)
        let thinking = "<think>Maybe {dairy}? No.</think>\n\(Self.clean)"
        #expect(try InsightReply.caseFile(from: thinking, context: context).suspects.count == 3)
        let wrapped = "{\"case_file\": \(Self.clean)}"
        #expect(try InsightReply.caseFile(from: wrapped, context: context).suspects.count == 3)
        let array = "[\(Self.clean)]"
        #expect(try InsightReply.caseFile(from: array, context: context).suspects.count == 3)
    }

    @Test func survivesMissingAndOddFields() throws {
        let minimal = try InsightReply.caseFile(from: #"{"plain_summary": "No clear pattern yet."}"#, context: context)
        #expect(minimal.suspects.isEmpty && !minimal.patternFound && minimal.nextExperiment == nil)
        #expect(minimal.summary == "No clear pattern yet.")

        let odd = """
        {"patternFound": "true", "suspects": [{"title": "new body wash (scented)", "confidence": "Low–Medium", "lag": 2},
                                               {"trigger": "Possible infection", "confidence": "high"},
                                               "Dry air"],
         "cannot_separate": "Wash and dry air started together.", "red_flags": "none",
         "next_experiment": "Stop the scented body wash for 14 days and keep everything else the same."}
        """
        let cf = try InsightReply.caseFile(from: odd, context: context)
        #expect(cf.patternFound)
        #expect(cf.suspects.map(\.kind) == [.newProduct, .dryAir])      // the symptom is dropped
        #expect(cf.suspects[0].title == "New body wash (scented)")
        #expect(cf.suspects[0].confidence == .lowMedium)
        #expect(cf.suspects[0].lag == "2 days")
        #expect(cf.suspects[1].startedOn != nil)
        #expect(cf.summary.contains("new body wash"))                    // generated when missing
        #expect(cf.cannotSeparate == ["Wash and dry air started together."])
        #expect(cf.redFlags.isEmpty)
        #expect(cf.nextExperiment?.title == "Stop the scented body wash")
        #expect(cf.nextExperiment?.lengthDays == 14)
        #expect(cf.nextExperiment?.trigger == .newProduct)
    }

    @Test func capsSuspectsAndKeepsRedFlags() throws {
        let many = """
        {"plain_summary": "s", "suspects": [{"trigger":"Dairy"},{"trigger":"Nuts"},{"trigger":"Wool"},{"trigger":"Pool"}],
         "red_flags": ["Yellow crusts and fever: see a doctor today."]}
        """
        let cf = try InsightReply.caseFile(from: many, context: context)
        #expect(cf.suspects.count == 3)
        #expect(cf.redFlags.count == 1)
    }

    @Test func rejectsGarbage() {
        #expect(throws: InsightReply.DecodeError.noJSON) { try InsightReply.caseFile(from: "I can't help with that.", context: context) }
        #expect(throws: InsightReply.DecodeError.nothingUseful) { try InsightReply.caseFile(from: "{\"foo\": 1}", context: context) }
    }

    @Test func parsesConfidenceWords() {
        #expect(Confidence.parse("Low–Medium") == .lowMedium)
        #expect(Confidence.parse("low_medium") == .lowMedium)
        #expect(Confidence.parse("low to moderate") == .lowMedium)
        #expect(Confidence.parse("moderate") == .medium)
        #expect(Confidence.parse("medium-high") == .medium)
        #expect(Confidence.parse("HIGH") == .high)
        #expect(Confidence.parse("0.6") == .medium)
        #expect(Confidence.parse("?") == nil)
        #expect(ExposureKind.parse("dry_air") == .dryAir)
        #expect(ExposureKind.parse("New product") == .newProduct)
        #expect(ExposureKind.guess(from: "hair dye") == .other)
        #expect(ExposureKind.guess(from: "Laundry detergent") == .detergent)
    }
}

// MARK: - Client + service (no network: a mock URL protocol)

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func chat(_ content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": "x", "choices": [["index": 0, "message": ["role": "assistant", "content": content], "finish_reason": "stop"]]])
    }
}

@Suite(.serialized) struct InsightServiceTests {
    let demo = DemoData.make(today: now, calendar: cal)

    @Test func requestFollowsTheContract() throws {
        let client = InsightClient(configuration: .init(model: "deepseek/deepseek-v4-flash", apiKey: "test-key"))
        let request = try client.makeRequest(system: "SYS", user: "USER")
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "deepseek/deepseek-v4-flash")
        #expect(body["temperature"] == nil)
        #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
    }

    @Test func replyTextHandlesShapesAndErrors() throws {
        #expect(try InsightClient.replyText(from: MockURLProtocol.chat("{}"), status: 200) == "{}")
        let parts = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": [["type": "text", "text": "{\"a\":"], ["type": "text", "text": "1}"]]]]]])
        #expect(try InsightClient.replyText(from: parts, status: 200) == "{\"a\":1}")
        let err = try JSONSerialization.data(withJSONObject: ["error": ["code": 402, "message": "Insufficient credits"]])
        #expect(throws: InsightClient.Failure.http(402, "Insufficient credits")) { try InsightClient.replyText(from: err, status: 402) }
        #expect(throws: InsightClient.Failure.http(500, "HTTP 500")) { try InsightClient.replyText(from: Data(), status: 500) }
        #expect(throws: InsightClient.Failure.emptyReply) { try InsightClient.replyText(from: MockURLProtocol.chat("  "), status: 200) }
    }

    @Test func noKeyUsesTheBundledAnalysis() async {
        let outcome = await InsightService.analyze(dataset: demo, apiKey: nil, model: "m", now: now, calendar: cal, session: MockURLProtocol.session)
        #expect(outcome.source == .bundled(.noKey))
        #expect(outcome.caseFile == demo.caseFile)
        #expect(outcome.stats.flares.count == 1)
    }

    @Test func liveReplyBecomesTheNextCaseFile() async throws {
        MockURLProtocol.handler = { _ in (200, MockURLProtocol.chat(InsightReplyTests.clean)) }
        let outcome = await InsightService.analyze(dataset: demo, apiKey: "k", model: "anthropic/claude-sonnet-5.5", now: now,
                                                   calendar: cal, session: MockURLProtocol.session)
        #expect(outcome.source == .live(model: "anthropic/claude-sonnet-5.5"))
        #expect(outcome.caseFile.number == (demo.caseFile?.number ?? 0) + 1)
        #expect(outcome.caseFile.producedBy == "claude-sonnet-5.5 · live")
        #expect(outcome.caseFile.suspects.first?.kind == .newProduct)
        let sent = try #require(MockURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer k")
    }

    @Test func errorsFallBack() async {
        MockURLProtocol.handler = { _ in (500, Data("oops".utf8)) }
        let failed = await InsightService.analyze(dataset: demo, apiKey: "k", model: "m", now: now, calendar: cal, session: MockURLProtocol.session)
        #expect(failed.source == .bundled(.failed))
        #expect(failed.caseFile == demo.caseFile)

        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = await InsightService.analyze(dataset: demo, apiKey: "k", model: "m", now: now, calendar: cal, session: MockURLProtocol.session)
        #expect(offline.source == .bundled(.offline))

        MockURLProtocol.handler = { _ in (200, MockURLProtocol.chat("Sorry, I can't do that.")) }
        let junk = await InsightService.analyze(dataset: demo, apiKey: "k", model: "m", now: now, calendar: cal, session: MockURLProtocol.session)
        #expect(junk.source == .bundled(.failed))
    }

    @Test func bundledCaseFileIsRebuiltWhenALiveOneReplacedIt() throws {
        var live = demo
        live.caseFile?.producedBy = "claude-sonnet-5.5 · live"
        let bundled = InsightService.bundledCaseFile(for: live, calendar: cal)
        #expect(bundled.producedBy.contains("bundled"))
        let wash = try #require(bundled.suspects.first)
        #expect(wash.startedOn == demo.days[DemoData.bodyWashDay].day)
        #expect(wash.flareOn == demo.days[DemoData.flareStartDay].day)
        #expect(InsightService.windowDays(bundled, calendar: cal) == 14)
    }
}

// MARK: - Experiment

@Suite struct ExperimentProgressTests {
    @Test func noExperimentNoProgress() {
        #expect(ExperimentProgress(dataset: DemoData.make(today: now, calendar: cal), calendar: cal) == nil)
    }

    @Test func runningDaySix() throws {
        let d = DemoData.make(today: now, experimentDay: 6, calendar: cal)
        let p = try #require(ExperimentProgress(dataset: d, calendar: cal))
        #expect(p.day == 6 && p.length == 10 && p.daysLeft == 4)
        #expect(!p.isFinished)
        #expect(p.fullDays == 5)
        #expect(p.perDay.compactMap { $0 }.count == 6)
        let expected = DemoData.experimentMinutes.prefix(5).reduce(0, +) / 5
        #expect(abs((p.during ?? 0) - expected) < 1)
        #expect(abs(p.before - 34.25) < 0.01)
        #expect((p.percentLess ?? 0) > 20)
        #expect(p.stillPresent.map(\.kind) == [.dryAir])                // the air stayed dry
        #expect((p.humidityDuring ?? 100) < 35)
    }

    @Test func dayOneHasNoFullDayYet() throws {
        let p = try #require(ExperimentProgress(dataset: DemoData.make(today: now, experimentDay: 1, calendar: cal), calendar: cal))
        #expect(p.day == 1 && p.during == nil && p.change == nil)
    }

    @Test func dayTenIsConfirmed() throws {
        let p = try #require(ExperimentProgress(dataset: DemoData.make(today: now, experimentDay: 10, calendar: cal), calendar: cal))
        #expect(p.day == 10 && p.daysLeft == 0 && p.isFinished)
        #expect(p.status == .confirmed)
        #expect((p.percentLess ?? 0) >= 40)
        #expect(p.progress == 1)
    }

    @Test func planSubject() {
        let plan = ExperimentPlan(title: "Pause the body wash", instruction: "", trigger: .newProduct, lengthDays: 10)
        #expect(plan.subject == "body wash")
        #expect(plan.shortSubject == "wash")
        #expect(ExperimentPlan(title: "Stop dairy for 10 days", instruction: "", trigger: .dairy, lengthDays: 10).subject == "dairy")
        #expect(ExperimentPlan(title: "Run a humidifier", instruction: "", trigger: .dryAir, lengthDays: 10).subject == nil)
    }
}
