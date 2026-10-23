import Foundation
import Security

/// Where the AI settings live (contract with Settings, which writes them).
/// - Model: `UserDefaults` key "aiModel" (default "anthropic/claude-sonnet-5.5").
/// - API key: Keychain generic password, service "com.jackyzhong.eczematwin2.ai", account "openrouter-api-key".
/// The key is only ever read here and put in the Authorization header; it is never logged or stored elsewhere.
public enum InsightCredentials {
    public static let keychainService = "com.jackyzhong.eczematwin2.ai"
    public static let keychainAccount = "openrouter-api-key"
    public static let modelDefaultsKey = "aiModel"
    public static let defaultModel = "anthropic/claude-sonnet-5.5"
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// The OpenRouter API key from the Keychain, or nil when none is set.
    public static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static var hasAPIKey: Bool { apiKey() != nil }

    /// The model id to call (an OpenRouter model id such as "anthropic/claude-sonnet-5.5").
    public static func model(_ defaults: UserDefaults = .standard) -> String {
        let m = defaults.string(forKey: modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    /// "anthropic/claude-sonnet-5.5" → "claude-sonnet-5.5".
    public static func shortName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }
}
