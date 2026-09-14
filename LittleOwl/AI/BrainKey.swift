#if LITTLE_OWL_AI
import Foundation
import Security

/// Where the API key lives.
///
/// The keychain rather than `UserDefaults`, for the ordinary reason — a key in a plist
/// is a key in every backup and every file browser — and for one specific to this app:
/// `PrivacyInfo.xcprivacy` declares exactly four `UserDefaults` keys under CA92.1, and a
/// secret is not one of the four things that declaration describes.
///
/// `.whenUnlockedThisDeviceOnly` because there is no reason for a parent's key to
/// follow them to another iPad through a backup. If they restore, they type it again.
enum BrainKey {

    private static let account = "com.syrkin.littleowl.brain"

    static var current: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    /// Stores a key, or clears it when handed nothing. Returns whether it worked, so the
    /// settings screen can say something truthful rather than pretending.
    @discardableResult
    static func set(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard let trimmed, !trimmed.isEmpty else { return true }

        var insert = query
        insert[kSecValueData as String] = Data(trimmed.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static var isSet: Bool { current != nil }
}
#endif
