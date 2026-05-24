//
//  CloudHTTP.swift
//  Payam
//
//  Tiny URLSession wrapper shared by the cloud endpoints we currently call:
//    GET  /v1/river?since=…           (payam-polling)
//    POST /v1/feeds                    (payam-polling)
//    GET  /v1/extractions/{hash}?url=… (payam-extract)
//
//  Centralizes base URLs, device-ID header bootstrapping, JSON decoding, and
//  status-code classification so each call site stays a one-liner.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum CloudHTTP {

    // TODO(auth): once auth ships these can move into a config / environment
    // file. They are deliberately inlined here because Phase 2 deploys exactly
    // one polling and one extraction stack.
    static let pollingBase = URL(string: "https://h439queahl.execute-api.us-west-2.amazonaws.com")!
    static let extractBase = URL(string: "https://kvzr90nd9a.execute-api.us-west-2.amazonaws.com")!

    /// Returned for non-2xx so callers can pattern-match on status (e.g. L0
    /// treats 422 as a silent fall-through, not an error to surface).
    struct HTTPStatusError: Error {
        let statusCode: Int
        let body: Data
    }

    /// Performs a GET, returns the decoded payload and the response. Attaches
    /// `User-Agent` and `x-payam-user` headers automatically.
    static func get<T: Decodable>(
        _ url: URL,
        as type: T.Type
    ) async throws -> (T, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Payam/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceID(), forHTTPHeaderField: "x-payam-user")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPStatusError(statusCode: http.statusCode, body: data)
        }

        let decoded = try JSONDecoder().decode(T.self, from: data)
        return (decoded, http)
    }

    /// Performs a POST with a JSON-encoded body. Attaches the same headers as
    /// `get`. Returns the decoded payload and the response.
    static func post<Body: Encodable, T: Decodable>(
        _ url: URL,
        body: Body,
        as type: T.Type
    ) async throws -> (T, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Payam/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID(), forHTTPHeaderField: "x-payam-user")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw HTTPStatusError(statusCode: http.statusCode, body: data)
        }

        let decoded = try JSONDecoder().decode(T.self, from: data)
        return (decoded, http)
    }

    /// Fetches a presigned URL's body without the device-ID header (S3 doesn't
    /// need it) and returns the raw bytes.
    static func fetchPresigned(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Device ID bootstrap

    /// Loads the per-install identifier from Keychain, generating + persisting
    /// one on first call. Identifier survives app deletion because Keychain does.
    static func deviceID() -> String {
        if let existing = KeychainService.loadDeviceID() {
            return existing
        }
        #if canImport(UIKit)
        let bootstrap = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let bootstrap = UUID().uuidString
        #endif
        KeychainService.saveDeviceID(bootstrap)
        return bootstrap
    }
}
