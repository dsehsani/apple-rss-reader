//
//  CloudAuthService.swift
//  Payam
//
//  Exchanges the Apple Sign-In identity token for a Payam cloud JWT.
//  Handles JWT storage in Keychain and silent refresh before expiry.
//

import Foundation

enum CloudAuthService {

    // MARK: - Response Types

    struct AuthResponse: Decodable {
        let jwt: String
        let expiresAt: TimeInterval
        let tier: String
        let tierExpiresAt: TimeInterval?
        let quotas: Quotas?

        struct Quotas: Decodable {
            let agentCallsRemaining: Int?
            let agentCallsResetAt: String?
        }
    }

    // MARK: - Token Exchange

    /// Sends the Apple identity token to the cloud auth endpoint and stores the JWT.
    /// Returns the auth response so the caller can update UserProfile with tier info.
    @discardableResult
    static func exchangeAppleToken(
        identityToken: Data,
        appleUserID: String
    ) async throws -> AuthResponse {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw PayamAPIClient.APIError.notAuthenticated
        }

        struct RequestBody: Encodable {
            let identityToken: String
            let appleUserID: String
        }

        let body = RequestBody(
            identityToken: tokenString,
            appleUserID: appleUserID
        )

        let response = try await PayamAPIClient.send(
            AuthResponse.self,
            method: "POST",
            path: "/v1/auth/apple",
            body: body,
            requiresAuth: false
        )

        // Store JWT and expiry
        KeychainService.saveJWT(response.jwt)
        UserDefaults.standard.set(response.expiresAt, forKey: "payam.jwt.expiresAt")

        return response
    }

    // MARK: - Token State

    /// Returns true if a JWT exists and hasn't expired.
    static var hasValidToken: Bool {
        #if DEBUG
        if AuthenticationManager.shared.debugForcePremium { return true }
        #endif
        guard KeychainService.loadJWT() != nil else { return false }
        let expiresAt = UserDefaults.standard.double(forKey: "payam.jwt.expiresAt")
        guard expiresAt > 0 else { return false }
        return Date().timeIntervalSince1970 < expiresAt
    }

    /// Returns true if the JWT will expire within the given interval.
    static func tokenExpiresWithin(_ seconds: TimeInterval) -> Bool {
        let expiresAt = UserDefaults.standard.double(forKey: "payam.jwt.expiresAt")
        guard expiresAt > 0 else { return true }
        return Date().timeIntervalSince1970 > (expiresAt - seconds)
    }

    // MARK: - Cleanup

    static func clearToken() {
        KeychainService.deleteJWT()
        UserDefaults.standard.removeObject(forKey: "payam.jwt.expiresAt")
    }
}
