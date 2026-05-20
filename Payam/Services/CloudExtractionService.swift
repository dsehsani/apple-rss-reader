//
//  CloudExtractionService.swift
//  Payam
//
//  L0 cloud extraction cache. Checks the server for a pre-extracted
//  article before falling through to on-device extraction (L1/L2/L3).
//  Device only sends sha256(url) — no user content is uploaded.
//

import Foundation
import CryptoKit

enum CloudExtractionService {

    // MARK: - Response

    private struct ExtractionResponse: Decodable {
        let title: String
        let author: String?
        let heroImageURL: String?
        let nodes: [ContentNode]
        let cachedAt: String?
    }

    // MARK: - Fetch

    /// Checks the cloud extraction cache for the given URL.
    /// Returns an ExtractedArticle on cache hit, nil on miss.
    static func fetch(
        articleURL: URL,
        itemID: UUID,
        feedName: String
    ) async -> ExtractedArticle? {
        let urlString = articleURL.absoluteString
        let urlHash = sha256(urlString)
        let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString

        do {
            let response = try await PayamAPIClient.send(
                ExtractionResponse.self,
                path: "/v1/extract/\(urlHash)?url=\(encodedURL)",
                timeout: 3 // Fast timeout — don't delay local fallback
            )

            return ExtractedArticle(
                id: itemID,
                sourceURL: articleURL,
                title: response.title,
                author: response.author,
                publishDate: nil,
                heroImageURL: response.heroImageURL.flatMap { URL(string: $0) },
                feedName: feedName,
                nodes: response.nodes,
                cachedAt: Date()
            )
        } catch {
            // Cache miss or network error — fall through to local extraction
            return nil
        }
    }

    // MARK: - Hash

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
