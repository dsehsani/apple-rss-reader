//
//  ContentFetcherService.swift
//  OpenRSS
//
//  Phase 2 — Content Fetching
//
//  Fetches the raw HTML of an article page from its canonical URL.
//  This HTML is handed off to Phase 3 (ReadabilityExtractionService)
//  for reader-mode extraction.
//
//  Cancellation: callers cancel via their owning Swift Task — URLSession
//  propagates task cancellation automatically through async/await.
//

import Foundation

// MARK: - Protocol (injectable / testable)

protocol ContentFetcherServiceProtocol: Sendable {
    /// Fetches the raw HTML string at `url`.
    func fetchHTML(from url: URL) async throws -> String
}

// MARK: - Errors

enum ContentFetcherError: LocalizedError {
    case badHTTPStatus(Int)
    case notHTMLContent(String)
    case emptyResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badHTTPStatus(let code):
            return "Server returned HTTP \(code)."
        case .notHTMLContent(let type):
            return "Expected HTML but received '\(type)'."
        case .emptyResponse:
            return "The server returned an empty response."
        case .decodingFailed:
            return "Could not decode the page as UTF-8 text."
        }
    }
}

// MARK: - ContentFetcherService

final class ContentFetcherService: ContentFetcherServiceProtocol {

    // MARK: - Configuration

    private let timeoutInterval: TimeInterval

    /// Shared ephemeral session so every ContentFetcherService instance
    /// doesn't allocate its own connection pool and TLS state.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config)
    }()

    init(timeoutInterval: TimeInterval = 15) {
        self.timeoutInterval = timeoutInterval
    }

    // MARK: - Public API

    func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"

        // Identify the app; some sites block generic URLSession user-agents
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) OpenRSS/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        // Signal that we want HTML, not a feed
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await Self.session.data(for: request)

        // Validate HTTP status
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw ContentFetcherError.badHTTPStatus(http.statusCode)
            }

            // Warn on non-HTML content types but don't hard-fail —
            // some servers omit the header or set it loosely
            if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
               !contentType.contains("text/html") && !contentType.contains("xhtml") {
                // Non-HTML Content-Type; proceed anyway as some servers omit it
            }
        }

        guard !data.isEmpty else {
            throw ContentFetcherError.emptyResponse
        }

        // Try UTF-8 first, fall back to Latin-1 (common on older sites)
        if let html = String(data: data, encoding: .utf8) {
            return html
        } else if let html = String(data: data, encoding: .isoLatin1) {
            return html
        } else {
            throw ContentFetcherError.decodingFailed
        }
    }
}
