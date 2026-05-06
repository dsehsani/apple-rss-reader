//
//  OGImageService.swift
//  OpenRSS
//
//  Lazily resolves Open Graph (and equivalent) hero images for articles
//  whose RSS feed provided no image URL.
//
//  Design:
//    • Swift actor — all state is actor-isolated, no locks needed.
//    • UserDefaults cache — persists across launches; each article URL
//      is fetched at most once per cache TTL.
//    • Negative cache — failed lookups are remembered for `negativeCacheTTL`
//      so the card doesn't refetch on every appearance and stop showing
//      the placeholder once we've concluded the page has no usable image.
//    • URLSession.bytes streaming — reads up to 32 KB then stops, so
//      we never download a full HTML page.  The stream is cancelled
//      automatically when the calling Task is cancelled (e.g. the card
//      scrolled off screen).
//    • inFlight set — deduplicates concurrent requests for the same URL.
//    • Resolution — relative, protocol-relative, and absolute-path URLs
//      are resolved against the article URL; http:// is upgraded to https://
//      for ATS compatibility (mirrors RSSService behavior).
//    • Fallbacks — og:image → og:image:secure_url → twitter:image →
//      <link rel="image_src"> → first <img src> in the streamed buffer.
//

import Foundation

// MARK: - OGImageService

actor OGImageService {

    // MARK: - Singleton

    static let shared = OGImageService()

    // MARK: - State

    /// article URL → resolved image URL string. Positive results only.
    private var cache: [String: String] = [:]

    /// article URL → unix-time expiry of the negative result. Stops us from
    /// refetching pages we already concluded have no usable image.
    private var negativeCache: [String: TimeInterval] = [:]

    /// Article URLs currently being fetched — prevents duplicate concurrent requests.
    private var inFlight: Set<String> = []

    private static let cacheKey = "openrss.ogImageCache"
    private static let negativeCacheKey = "openrss.ogImageNegativeCache"

    /// How long a negative result is honored before we re-attempt the fetch.
    private static let negativeCacheTTL: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    /// Browser-like User-Agent — some hosts return 403 or non-HTML to
    /// custom UAs, which kills our extraction silently.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Init

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] {
            cache = saved
        }
        if let savedNegative = UserDefaults.standard.dictionary(forKey: Self.negativeCacheKey) as? [String: Double] {
            // Drop expired entries on load so we eventually re-try sites
            // that may have added og:image since we last looked.
            let now = Date().timeIntervalSince1970
            negativeCache = savedNegative.filter { $0.value > now }
        }
    }

    // MARK: - Public API

    /// Returns the cached image URL for `articleURL`, or `nil` if not yet resolved.
    func cachedImageURL(for articleURL: String) -> String? {
        cache[articleURL]
    }

    /// Fetches and caches the image URL for `articleURL` if not already known.
    /// Concurrent calls for the same URL are deduplicated via `inFlight`.
    /// The fetch is automatically cancelled if the calling Task is cancelled.
    /// Negative results are also cached (with a TTL) so we don't refetch
    /// pages we already failed to extract from.
    func prefetch(articleURL: String) async {
        guard cache[articleURL] == nil,
              !inFlight.contains(articleURL),
              let url = URL(string: articleURL)
        else { return }

        // Honor negative cache: if we recently failed, skip until the entry expires.
        if let expiry = negativeCache[articleURL], expiry > Date().timeIntervalSince1970 {
            return
        }

        inFlight.insert(articleURL)
        defer { inFlight.remove(articleURL) }

        if let imageURL = await Self.fetchImageURL(from: url) {
            cache[articleURL] = imageURL
            negativeCache.removeValue(forKey: articleURL)
            UserDefaults.standard.set(cache, forKey: Self.cacheKey)
            UserDefaults.standard.set(negativeCache, forKey: Self.negativeCacheKey)
        } else {
            negativeCache[articleURL] = Date().timeIntervalSince1970 + Self.negativeCacheTTL
            UserDefaults.standard.set(negativeCache, forKey: Self.negativeCacheKey)
        }
    }

    // MARK: - Fetch (static — accesses no actor state)

    /// Streams the article page up to 32 KB, stopping early once `</head>`
    /// is seen, then extracts a usable hero image URL.
    private static func fetchImageURL(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            // Skip explicitly-binary content types (PDFs, images, JSON APIs, etc.).
            // Many HN links go to PDFs and GitHub releases where extraction is hopeless.
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let nonHTMLPrefixes = [
                "image/", "audio/", "video/", "font/",
                "application/pdf", "application/zip",
                "application/octet-stream", "application/json"
            ]
            if nonHTMLPrefixes.contains(where: { contentType.hasPrefix($0) }) {
                return nil
            }

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

            // Resolve any extracted candidate against the final response URL so
            // relative URLs become absolute. Fall back to the original request URL.
            let baseURL = http.url ?? url
            return extractImageURL(from: html, baseURL: baseURL)
        } catch {
            // Includes CancellationError when the card scrolls off screen — silently stop.
            return nil
        }
    }

    // MARK: - Extraction

    /// Extracts a hero image URL from a partial HTML string, trying several
    /// well-known meta tags before falling back to the first `<img>` tag.
    /// Resolves relative URLs against `baseURL` and upgrades http:// → https://.
    private static func extractImageURL(from html: String, baseURL: URL) -> String? {
        // 1. Open Graph and Twitter card meta tags (in priority order).
        let metaProperties = [
            "og:image:secure_url",
            "og:image",
            "twitter:image",
            "twitter:image:src"
        ]
        for property in metaProperties {
            if let candidate = matchMetaContent(html: html, property: property),
               let resolved = resolveAndUpgrade(candidate, baseURL: baseURL) {
                return resolved
            }
        }

        // 2. <link rel="image_src" href="...">
        if let candidate = matchLinkHref(html: html, rel: "image_src"),
           let resolved = resolveAndUpgrade(candidate, baseURL: baseURL) {
            return resolved
        }

        // 3. First <img src="..."> in the streamed buffer (longshot — buffer
        //    usually stops at </head>, but some sites put preload imgs early).
        if let candidate = firstImgSrc(in: html),
           let resolved = resolveAndUpgrade(candidate, baseURL: baseURL) {
            return resolved
        }

        return nil
    }

    /// Matches `<meta property|name="<property>" content="<URL>">` (and reversed attribute order).
    private static func matchMetaContent(html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+?(?:property|name)=["']\#(escaped)["'][^>]+?content=["']([^"']+)["']"#,
            #"<meta[^>]+?content=["']([^"']+)["'][^>]+?(?:property|name)=["']\#(escaped)["']"#
        ]
        for pattern in patterns {
            if let captured = firstCapture(in: html, pattern: pattern) {
                return captured
            }
        }
        return nil
    }

    /// Matches `<link rel="<rel>" href="<URL>">` (and reversed attribute order).
    private static func matchLinkHref(html: String, rel: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: rel)
        let patterns = [
            #"<link[^>]+?rel=["']\#(escaped)["'][^>]+?href=["']([^"']+)["']"#,
            #"<link[^>]+?href=["']([^"']+)["'][^>]+?rel=["']\#(escaped)["']"#
        ]
        for pattern in patterns {
            if let captured = firstCapture(in: html, pattern: pattern) {
                return captured
            }
        }
        return nil
    }

    /// Returns the src of the first `<img>` tag found in the buffer.
    /// Handles both single- and double-quoted src values.
    private static func firstImgSrc(in html: String) -> String? {
        let pattern = #"<img\b[^>]*?\bsrc=(?:"([^"]+)"|'([^']+)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: nsRange) {
            for groupIdx in 1...2 where groupIdx < match.numberOfRanges {
                guard let r = Range(match.range(at: groupIdx), in: html) else { continue }
                let candidate = String(html[r])
                    .replacingOccurrences(of: "&amp;", with: "&")
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    /// First capture group of the first match, with `&amp;` decoded.
    private static func firstCapture(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: nsRange),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[captureRange])
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Resolves `candidate` against `baseURL` (handles `//host/...`, `/path/...`,
    /// and full URLs), then upgrades http:// → https:// for ATS compatibility.
    /// Returns nil if the result isn't a usable absolute http(s) URL.
    private static func resolveAndUpgrade(_ candidate: String, baseURL: URL) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved: URL?
        if trimmed.hasPrefix("//") {
            // Protocol-relative URL — prepend the base URL's scheme.
            let scheme = baseURL.scheme ?? "https"
            resolved = URL(string: "\(scheme):\(trimmed)")
        } else {
            resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
        }

        guard var absolute = resolved?.absoluteString else { return nil }
        guard absolute.hasPrefix("http://") || absolute.hasPrefix("https://") else { return nil }

        // Upgrade http:// to https:// for ATS compatibility (mirrors RSSService).
        if absolute.hasPrefix("http://") {
            absolute = "https://" + absolute.dropFirst(7)
        }

        return absolute
    }
}
