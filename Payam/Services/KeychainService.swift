//
//  KeychainService.swift
//  Payam
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
    private static let jwtKey = "cloudJWT"

    // MARK: - Save

    /// Stores the Apple user identifier in Keychain.
    @discardableResult
    static func saveAppleUserID(_ userID: String) -> Bool {
        save(key: appleUserIDKey, value: userID)
    }

    /// Retrieves the stored Apple user identifier, or nil if not found.
    static func loadAppleUserID() -> String? {
        load(key: appleUserIDKey)
    }

    /// Removes the stored Apple user identifier from Keychain.
    @discardableResult
    static func deleteAppleUserID() -> Bool {
        delete(key: appleUserIDKey)
    }

    // MARK: - JWT

    @discardableResult
    static func saveJWT(_ token: String) -> Bool {
        save(key: jwtKey, value: token)
    }

    static func loadJWT() -> String? {
        load(key: jwtKey)
    }

    @discardableResult
    static func deleteJWT() -> Bool {
        delete(key: jwtKey)
    }

    // MARK: - Generic Helpers

    private static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    @discardableResult
    private static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
