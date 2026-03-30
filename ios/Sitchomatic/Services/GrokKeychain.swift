import Foundation
import Security

/// Secure Keychain storage for the Grok (xAI) API key.
/// The API key is never stored in source code — it is persisted in the iOS Keychain,
/// which is encrypted at rest by the Secure Enclave.
nonisolated final class GrokKeychain: Sendable {
    static let shared = GrokKeychain()

    private let service = "com.sitchomatic.grok"
    private let account = "grok-api-key"

    /// Stores the API key securely in the Keychain.
    @discardableResult
    func setAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Remove existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the API key from the Keychain.
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the API key from the Keychain.
    @discardableResult
    func removeAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// Returns true if an API key is stored.
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
