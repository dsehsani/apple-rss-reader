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

    /// Streams the article page up to 64 KB, stopping early once `</head>` is
    /// seen, then extracts the highest-resolution og:image URL.
    private static func fetchOGImage(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("OpenRSS/1.0 (iOS; SwiftUI)", forHTTPHeaderField: "User-Agent")

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            var buffer = Data()
            buffer.reserveCapacity(65_536)

            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 65_536 { break }
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

    /// Extracts the highest-resolution og:image URL from a partial HTML string.
    ///
    /// Parses ALL og:image meta tags in document order and associates each with its
    /// following og:image:width tag (if any). Returns the URL with the highest width,
    /// or the last URL found when no width metadata is present (many sites list the
    /// largest variant last).
    private static func extractOGImage(from html: String) -> String? {
        // Match every <meta> tag in the <head> section
        guard let metaRegex = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*?>"#, options: .caseInsensitive
        ) else { return nil }

        struct Candidate { var url: String; var width: Int = 0 }
        var candidates: [Candidate] = []

        // Patterns to pull content= and property= values out of a single meta tag
        let contentRegex = try? NSRegularExpression(
            pattern: #"content=["']([^"']+)["']"#, options: .caseInsensitive)
        let propertyRegex = try? NSRegularExpression(
            pattern: #"(?:property|name)=["'](og:[^"']+)["']"#, options: .caseInsensitive)

        func attr(_ regex: NSRegularExpression?, in tag: String) -> String? {
            let ns = NSRange(tag.startIndex..., in: tag)
            guard let m = regex?.firstMatch(in: tag, range: ns),
                  let r = Range(m.range(at: 1), in: tag) else { return nil }
            return String(tag[r])
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        for match in metaRegex.matches(in: html, range: nsRange) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])

            guard let property = attr(propertyRegex, in: tag) else { continue }

            if property.caseInsensitiveCompare("og:image") == .orderedSame {
                guard var url = attr(contentRegex, in: tag) else { continue }
                url = url.replacingOccurrences(of: "&amp;", with: "&")
                if url.hasPrefix("http") {
                    candidates.append(Candidate(url: url))
                }
            } else if property.caseInsensitiveCompare("og:image:width") == .orderedSame,
                      let widthStr = attr(contentRegex, in: tag),
                      let width = Int(widthStr),
                      !candidates.isEmpty {
                // Associate this width with the most recently seen og:image candidate
                candidates[candidates.count - 1].width = width
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Prefer the candidate with the largest known width; fall back to last (sites often
        // list low-res first and high-res last when no width metadata is provided).
        if candidates.contains(where: { $0.width > 0 }) {
            return candidates.max(by: { $0.width < $1.width })?.url
        }
        return candidates.last?.url
    }
}
