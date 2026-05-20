//
//  PayamAPIClient.swift
//  Payam
//
//  Shared HTTP client for all Payam cloud endpoints.
//  Attaches JWT authorization, handles 401 retry via CloudAuthService.
//

import Foundation

enum PayamAPIClient {

    // MARK: - Configuration

    private static var baseURL: String {
        APIKeys.payamChatBaseURL.trimmingCharacters(in: .init(charactersIn: "/ "))
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case noBaseURL
        case notAuthenticated
        case http(Int, String?)
        case decodingFailed(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noBaseURL:          return "Cloud service not configured."
            case .notAuthenticated:   return "Not signed in to Payam Cloud."
            case .http(let code, let msg):
                return "Server error (\(code))" + (msg.map { ": \($0)" } ?? "")
            case .decodingFailed(let err): return "Bad response: \(err.localizedDescription)"
            case .networkError(let err):   return err.localizedDescription
            }
        }
    }

    // MARK: - Request Building

    static func request(
        method: String = "GET",
        path: String,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else {
            throw APIError.noBaseURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30

        if requiresAuth {
            guard let jwt = KeychainService.loadJWT() else {
                throw APIError.notAuthenticated
            }
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        return req
    }

    // MARK: - Execute

    static func send<T: Decodable>(
        _ type: T.Type,
        method: String = "GET",
        path: String,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let req = try request(method: method, path: path, body: body, requiresAuth: requiresAuth)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, nil)
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = try? JSONDecoder().decode([String: String].self, from: data)["error"]
            throw APIError.http(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// Fire-and-forget request that only checks for HTTP success.
    static func sendNoContent(
        method: String = "POST",
        path: String,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws {
        let req = try request(method: method, path: path, body: body, requiresAuth: requiresAuth)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = try? JSONDecoder().decode([String: String].self, from: data)["error"]
            throw APIError.http(code, msg)
        }
    }
}
