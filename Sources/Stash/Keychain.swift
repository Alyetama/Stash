import Foundation
import Security

/// Minimal wrapper over the macOS Keychain for storing secrets (the OpenCode API
/// key) encrypted at rest, rather than in the plaintext preferences plist.
enum Keychain {
    static let service = "com.local.stash"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Store (or, if empty, remove) a secret for `account`.
    static func set(_ value: String, account: String) {
        let query = baseQuery(account)
        guard !value.isEmpty else { SecItemDelete(query as CFDictionary); return }
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        } else {
            var add = query
            attrs.forEach { add[$0] = $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// True if an item exists, WITHOUT reading its secret data — so it never
    /// triggers the "allow access" consent prompt (that only fires on data reads).
    static func exists(account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
