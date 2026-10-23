import Foundation

/// Calls an OpenAI-compatible chat endpoint (OpenRouter) with the stats + daily log and decodes the
/// JSON reply into a `CaseFile`. Use `InsightService.analyze` for the full flow with the offline fallback.
public struct InsightClient: Sendable {
    public struct Configuration: Sendable {
        public var endpoint: URL
        public var model: String
        public var apiKey: String
        public var timeout: TimeInterval
        /// Room for the model's own thinking plus the JSON reply (thinking counts against it on Claude).
        public var maxTokens: Int

        public init(endpoint: URL = InsightCredentials.endpoint, model: String, apiKey: String,
                    timeout: TimeInterval = 60, maxTokens: Int = 8000) {
            self.endpoint = endpoint; self.model = model; self.apiKey = apiKey; self.timeout = timeout; self.maxTokens = maxTokens
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case noSystemPrompt
        case offline
        case network(String)
        /// HTTP status and the provider's error message (never contains the key).
        case http(Int, String)
        case emptyReply
        case badReply(String)
    }

    public var configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// The HTTP request for one analysis. Nothing here is logged.
    public func makeRequest(system: String, user: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Eczema Twin", forHTTPHeaderField: "X-Title")
        // No temperature: newer Claude models reject non-default sampling settings.
        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Runs the analysis and returns a live case file, or throws `Failure`.
    public func analyze(dataset: TwinDataset, stats: InsightStats, number: Int, now: Date = Date(),
                        calendar: Calendar = .current) async throws -> CaseFile {
        guard let system = InsightPrompt.systemPrompt() else { throw Failure.noSystemPrompt }
        let user = InsightPrompt.userMessage(dataset: dataset, stats: stats, now: now, calendar: calendar)
        let request = try makeRequest(system: system, user: user)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw Failure.offline
            default:
                throw Failure.network(error.code == .timedOut ? "timed out" : "network error \(error.code.rawValue)")
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let content = try Self.replyText(from: data, status: status)
        let context = InsightReply.Context(stats: stats, number: number, createdAt: now,
                                           producedBy: "\(InsightCredentials.shortName(configuration.model)) · live")
        do {
            return try InsightReply.caseFile(from: content, context: context)
        } catch {
            throw Failure.badReply("\(error)")
        }
    }

    /// Pulls `choices[0].message.content` out of an OpenAI-compatible response (or the provider's error).
    public static func replyText(from data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            let code = (error["code"] as? Int) ?? status
            throw Failure.http(code == 0 ? status : code, (error["message"] as? String).map { String($0.prefix(200)) } ?? "error")
        }
        guard (200..<300).contains(status) else { throw Failure.http(status, "HTTP \(status)") }
        guard let choices = json?["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any]
        else { throw Failure.emptyReply }
        var text = ""
        if let s = message["content"] as? String {
            text = s
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.emptyReply }
        return text
    }
}
