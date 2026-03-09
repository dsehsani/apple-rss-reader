//
//  OGImageService.swift
//  OpenRSS
//
//  Lazily resolves Open Graph images for articles whose RSS feed
//  provided no image URL.
//
//  Design:
//    • Swift actor — all state is actor-isolated, no locks needed.
//    • UserDefaults cache — persists across launches; each article URL
//      is fetched at most once, ever.
//    • URLSession.bytes streaming — reads up to 32 KB then stops, so
//      we never download a full HTML page.  The stream is cancelled
//      automatically when the calling Task is cancelled (e.g. the card
//      scrolled off screen).
//    • inFlight set — deduplicates concurrent requests for the same URL.
//

import Foundation

// MARK: - OGImageService

actor OGImageService {

    // MARK: - Singleton

    static let shared = OGImageService()

    // MARK: - State

    /// article URL → resolved og:image URL string
    private var cache: [String: String] = [:]

    /// Article URLs currently being fetched — prevents duplicate concurrent requests.
    private var inFlight: Set<String> = []

    private static let cacheKey = "openrss.ogImageCache"

    // MARK: - Init

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] {
            cache = saved
        }
    }

    // MARK: - Public API

    /// Returns the cached og:image URL for `articleURL`, or `nil` if not yet resolved.
    func cachedImageURL(for articleURL: String) -> String? {
        cache[articleURL]
    }

    /// Fetches and caches the og:image for `articleURL` if not already known.
    /// Concurrent calls for the same URL are deduplicated via `inFlight`.
    /// The fetch is automatically cancelled if the calling Task is cancelled.
    func prefetch(articleURL: String) async {
        guard cache[articleURL] == nil,
              !inFlight.contains(articleURL),
              let url = URL(string: articleURL)
        else { return }

        inFlight.insert(articleURL)
        defer { inFlight.remove(articleURL) }

        guard let imageURL = await Self.fetchOGImage(from: url) else { return }
        cache[articleURL] = imageURL
        UserDefaults.standard.set(cache, forKey: Self.cacheKey)
    }

    // MARK: - Fetch (static — accesses no actor state)

    /// Streams the article page up to 32 KB, stopping early once `</head>` is
    /// seen, then extracts the og:image content value.
    private static func fetchOGImage(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("OpenRSS/1.0 (iOS; SwiftUI)", forHTTPHeaderField: "User-Agent")

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            var buffer = Data()
            buffer.reserveCapacity(32_768)

            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 32_768 { break }
                // Check for end of <head> every 512 bytes to avoid scanning every byte.
                if buffer.count % 512 == 0,
                   let partial = String(data: buffer, encoding: .utf8),
                   partial.contains("</head>") { break }
            }

            guard let html = String(data: buffer, encoding: .utf8)
                          ?? String(data: buffer, encoding: .isoLatin1)
            else { return nil }

            return extractOGImage(from: html)
        } catch {
            // Includes CancellationError when the card scrolls off screen — silently stop.
            return nil
        }
    }

    // MARK: - Extraction

    /// Extracts the og:image URL from a partial HTML string.
    /// Handles both attribute orderings (property before content, and vice versa).
    private static func extractOGImage(from html: String) -> String? {
        // Pattern A: <meta property="og:image" content="URL">
        // Pattern B: <meta content="URL" property="og:image">
        let patterns = [
            #"<meta[^>]+?(?:property|name)=["']og:image["'][^>]+?content=["']([^"']+)["']"#,
            #"<meta[^>]+?content=["']([^"']+)["'][^>]+?(?:property|name)=["']og:image["']"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: .caseInsensitive
            ) else { continue }

            let nsRange = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: nsRange),
                  let srcRange = Range(match.range(at: 1), in: html)
            else { continue }

            var candidate = String(html[srcRange])
            // Decode the one entity that commonly appears in URLs inside HTML attributes.
            candidate = candidate.replacingOccurrences(of: "&amp;", with: "&")
            if candidate.hasPrefix("http") { return candidate }
        }
        return nil
    }
}
