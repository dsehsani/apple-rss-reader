//
//  KeychainService.swift
//  OpenRSS
//
//  Lightweight wrapper around the Security framework for persisting
//  the Apple user identifier across app installs.
//

import Foundation
import Security

/// Provides secure Keychain storage for the Apple user identifier.
///
/// The Apple user ID must survive app deletion and reinstall so the app
/// can silently re-authenticate without requiring a new Sign in with Apple flow.
/// UserDefaults does not survive reinstalls; Keychain does.
enum KeychainService {

    // MARK: - Constants

    private static let service = "com.openrss.auth"
    private static let appleUserIDKey = "appleUserID"

    // MARK: - Save

    /// Stores the Apple user identifier in Keychain.
    /// Overwrites any existing value for the same key.
    @discardableResult
    static func saveAppleUserID(_ userID: String) -> Bool {
        guard let data = userID.data(using: .utf8) else { return false }

        // Delete any existing item first to avoid errSecDuplicateItem
        deleteAppleUserID()

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  appleUserIDKey,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Load

    /// Retrieves the stored Apple user identifier, or nil if not found.
    static func loadAppleUserID() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  appleUserIDKey,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let userID = String(data: data, encoding: .utf8)
        else { return nil }

        return userID
    }

    // MARK: - Delete

    /// Removes the stored Apple user identifier from Keychain.
    @discardableResult
    static func deleteAppleUserID() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  appleUserIDKey,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
