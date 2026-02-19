//
//  YouTubeService.swift
//  OpenRSS
//
//  Resolves YouTube channel/handle URLs to their Atom RSS feed URL and
//  provides helpers for detecting YouTube video articles.
//
//  Supported channel URL formats → resolved to RSS:
//    youtube.com/feeds/videos.xml?channel_id=UC…  (already an RSS URL)
//    youtube.com/channel/UCxxxxxxxxxx             (direct construction)
//    youtube.com/@handle                          (page scrape)
//    youtube.com/c/CustomName                     (page scrape)
//    youtube.com/user/Username                    (page scrape)
//

import Foundation

// MARK: - YouTubeService

final class YouTubeService {

    // MARK: - Errors

    enum YouTubeError: LocalizedError {
        case notYouTubeURL
        case couldNotResolveChannelID

        var errorDescription: String? {
            switch self {
            case .notYouTubeURL:
                return "Not a YouTube URL."
            case .couldNotResolveChannelID:
                return "Could not find the YouTube channel RSS feed. Try pasting the channel's RSS URL directly (youtube.com/feeds/videos.xml?channel_id=…)."
            }
        }
    }

    // MARK: - Detection

    /// True if `url` points to any YouTube domain.
    static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host == "www.youtube.com"
            || host == "m.youtube.com" || host == "youtu.be"
    }

    /// True if `urlString` is a YouTube video watch URL (youtube.com/watch?v=… or youtu.be/…).
    static func isYouTubeVideoURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        if host == "youtu.be" { return true }
        if (host == "youtube.com" || host == "www.youtube.com") && url.path == "/watch" { return true }
        return false
    }

    /// Extracts the video ID from a YouTube watch URL.
    static func videoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }
        if host == "youtu.be" {
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value
    }

    /// Returns a high-quality thumbnail URL for the given video ID.
    static func thumbnailURL(videoID: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }

    // MARK: - RSS Resolution

    /// Converts any YouTube channel URL to its Atom RSS feed URL.
    func resolveRSSFeedURL(from url: URL) async throws -> URL {
        let path = url.path

        // Already an RSS feed URL
        if path.hasPrefix("/feeds/videos.xml") {
            return url
        }

        // /channel/UCxxxxxxxxxx — extract channel ID directly
        if path.hasPrefix("/channel/") {
            let channelID = path
                .dropFirst("/channel/".count)
                .components(separatedBy: "/")[0]
            guard !channelID.isEmpty else { throw YouTubeError.couldNotResolveChannelID }
            return try makeRSSURL(channelID: channelID)
        }

        // @handle, /c/name, /user/name — scrape the channel page
        return try await scrapeRSSLink(from: url)
    }

    // MARK: - Private Helpers

    private func makeRSSURL(channelID: String) throws -> URL {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)") else {
            throw YouTubeError.couldNotResolveChannelID
        }
        return url
    }

    /// Fetches the YouTube channel page and finds the embedded RSS <link> tag.
    private func scrapeRSSLink(from channelURL: URL) async throws -> URL {
        var request = URLRequest(url: channelURL, timeoutInterval: 15)
        // Mobile UA avoids some bot-detection redirects
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        // 1. Try <link rel="alternate" type="application/rss+xml" href="...">
        if let rssString = extractRSSHref(from: html), let rssURL = URL(string: rssString) {
            return rssURL
        }

        // 2. Fallback: find the channelId JSON value in the page
        if let channelID = extractChannelID(from: html) {
            return try makeRSSURL(channelID: channelID)
        }

        throw YouTubeError.couldNotResolveChannelID
    }

    private func extractRSSHref(from html: String) -> String? {
        let patterns = [
            #"<link[^>]+type="application/rss\+xml"[^>]+href="([^"]+)""#,
            #"<link[^>]+href="([^"]+feeds/videos\.xml[^"]+)""#,
        ]
        let nsRange = NSRange(html.startIndex..., in: html)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: nsRange),
                  let captureRange = Range(match.range(at: 1), in: html) else { continue }
            return String(html[captureRange])
        }
        return nil
    }

    private func extractChannelID(from html: String) -> String? {
        let pattern = #""channelId"\s*:\s*"(UC[a-zA-Z0-9_-]{22})""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}
