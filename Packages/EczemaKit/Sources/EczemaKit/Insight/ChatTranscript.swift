import Foundation

/// The chat's fixed words and the rules of a conversation (chat.js).
public enum ChatRules {
    public static let greeting = "Hi Douglas. I can read your scratching, sleep, weather, calendar and orders. Ask me anything about your skin."
    public static let suggestions = ["Why has my eczema been so bad the last few nights?", "How did I sleep this week?"]
    /// The suggested reply when Claude stops before its conclusion without asking anything.
    public static let nudge = "Go ahead"
    /// Replies Claude may take in one go before the app stops asking (a safety net; a conversation needs ~6).
    public static let maxRounds = 16

    /// Claude has shown its conclusion in this conversation.
    public static func concluded(_ messages: [ChatMessage]) -> Bool {
        messages.contains { $0.toolCalls.contains { $0.name == ChatTools.conclusion } }
    }

    /// Offer "Go ahead" after a turn that ended with `text`: not once concluded, and not when Claude asked
    /// something in its text (Douglas answers in the box).
    public static func offersNudge(after text: String, in messages: [ChatMessage]) -> Bool {
        !concluded(messages) && !text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }

    /// The text of Claude's reply as shown: trimmed, without a question it also asks on a question card (any
    /// case, with or without its "?"), and without the lead-in it leaves dangling ("… other things. First:").
    public static func shownText(_ message: ChatMessage) -> String {
        var text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        for call in message.toolCalls where call.name == ChatTools.question {
            let question = (call.argumentsObject["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { continue }
            var range = text.range(of: question, options: .caseInsensitive)
            if range == nil, question.hasSuffix("?"), question.count > 12,
               let bare = text.range(of: String(question.dropLast()), options: .caseInsensitive) {
                let next = bare.upperBound < text.endIndex && text[bare.upperBound] == "?" ? text.index(after: bare.upperBound) : bare.upperBound
                range = bare.lowerBound..<next
            }
            guard let range else { continue }
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lead = text.range(of: #"(?:^|(?<=[.!?…]))\s*[A-Za-z][A-Za-z'’ ]{0,24}[:,–—-]$"#, options: .regularExpression) {
                text.removeSubrange(lead)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}

/// A finished conversation as it is saved and replayed: every message (tool results included), when it began
/// (the dates its cards use) and how long each reply took (the rhythm of a replay).
public struct ChatTranscript: Codable, Hashable, Sendable {
    public var version: Int
    /// The model that answered.
    public var model: String
    public var startedAt: Date
    public var messages: [ChatMessage]
    /// Milliseconds per assistant reply, in order.
    public var latencies: [Int]

    public init(model: String, startedAt: Date, messages: [ChatMessage], latencies: [Int]) {
        version = 1
        self.model = model
        self.startedAt = startedAt
        self.messages = messages
        self.latencies = latencies
    }

    /// The saved result of each tool call, by call id.
    public var toolResults: [String: String] {
        var results: [String: String] = [:]
        for m in messages where m.role == .tool { if let id = m.toolCallID { results[id] = m.content } }
        return results
    }
}

/// Where the last finished conversation of each model is kept: one JSON file per model.
public enum ChatArchive {
    /// Application Support/Chat.
    public static var defaultDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chat", isDirectory: true)
    }

    static func fileName(for model: String) -> String {
        let safe = model.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "chat-\(String(safe)).json"
    }

    /// Saves `transcript` as the last conversation of its model.
    public static func save(_ transcript: ChatTranscript, in directory: URL = defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(transcript)
        try data.write(to: directory.appendingPathComponent(fileName(for: transcript.model)), options: .atomic)
    }

    /// The conversation to replay: the newest one with `model` (a development model), else the newest one
    /// with Claude, else the newest one at all.
    public static func load(preferring model: String? = nil, in directory: URL = defaultDirectory) -> ChatTranscript? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let all = files
            .filter { $0.lastPathComponent.hasPrefix("chat-") && $0.pathExtension == "json" }
            .compactMap { url -> ChatTranscript? in
                guard let data = try? Data(contentsOf: url),
                      let t = try? decoder.decode(ChatTranscript.self, from: data), t.version == 1, !t.messages.isEmpty else { return nil }
                return t
            }
            .sorted { $0.startedAt > $1.startedAt }
        if let model, let match = all.first(where: { $0.model == model }) { return match }
        return all.first { $0.model.hasPrefix("anthropic/") } ?? all.first
    }
}
