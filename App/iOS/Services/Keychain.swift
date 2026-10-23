import Foundation
import Security

/// AI settings contract (Settings writes, Insight reads):
/// - UserDefaults "aiModel": OpenRouter model slug, default "anthropic/claude-sonnet-5.5".
/// - Keychain generic password, service "com.jackyzhong.eczematwin2.ai", account "openrouter-api-key".
/// The key is never printed, logged or sent anywhere but OpenRouter (by Insight).
enum SettingsAI {
    static let modelKey = "aiModel"
    static let defaultModel = "anthropic/claude-sonnet-5.5"

    static var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    /// Models offered in Settings (any other OpenRouter slug can be typed in).
    static let presets: [(name: String, slug: String, note: String)] = [
        ("Claude Sonnet 5.5", "anthropic/claude-sonnet-5.5", "Best for the demo"),
        ("Claude Opus 5.5", "anthropic/claude-opus-5.5", "Most careful"),
        ("Claude Haiku 5.5", "anthropic/claude-haiku-5.5", "Fastest"),
        ("DeepSeek V4.1 Flash", "deepseek/deepseek-v4.1-flash", "Cheap, for testing"),
    ]
}

enum SettingsKeychain {
    static let service = "com.jackyzhong.eczematwin2.ai"
    static let account = "openrouter-api-key"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The stored key, or nil.
    static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static var hasKey: Bool {
        var query = base
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Saves (or replaces) the key. Returns false if the Keychain refused it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// OSStatus of a raw add + delete of a throwaway item under another account (diagnostics only).
    static func probe() -> OSStatus {
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: "qa-probe",
                                   kSecValueData as String: Data("x".utf8)]
        let status = SecItemAdd(item as CFDictionary, nil)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: "qa-probe"] as CFDictionary)
        return status
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(base as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
