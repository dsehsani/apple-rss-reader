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
        let path = "/v1/extract/\(urlHash)?url=\(encodedURL)"

        // First attempt — may return 200 (cache hit) or 202 (queued for extraction)
        if let result = await attempt(path: path, itemID: itemID, sourceURL: articleURL, feedName: feedName) {
            return result
        }

        // On 202, the server queued extraction. Wait briefly and retry once.
        try? await Task.sleep(for: .seconds(5))

        return await attempt(path: path, itemID: itemID, sourceURL: articleURL, feedName: feedName)
    }

    private static func attempt(
        path: String,
        itemID: UUID,
        sourceURL: URL,
        feedName: String
    ) async -> ExtractedArticle? {
        do {
            let response = try await PayamAPIClient.send(
                ExtractionResponse.self,
                path: path,
                timeout: 3
            )

            return ExtractedArticle(
                id: itemID,
                sourceURL: sourceURL,
                title: response.title,
                author: response.author,
                publishDate: nil,
                heroImageURL: response.heroImageURL.flatMap { URL(string: $0) },
                feedName: feedName,
                nodes: response.nodes,
                cachedAt: Date()
            )
        } catch {
            return nil
        }
    }

    // MARK: - Hash

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
