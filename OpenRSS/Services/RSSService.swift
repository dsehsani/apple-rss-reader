//
//  RSSService.swift
//  OpenRSS
//
//  Created by Awaab Mirghani on 2/15/26.
//

import Foundation
import FeedKit

// MARK: - ParsedArticle
struct ParsedArticle {
    let title: String?
    let link: String?
    let publicationDate: Date?
    let description: String?
    let imageURL: String?
    let author: String?
    /// Audio enclosure URL if the feed item carries an audio attachment (e.g. podcast).
    let audioURL: String?
}

// MARK: - RSSServiceError
enum RSSServiceError: LocalizedError {
    case parsingFailed(Error)
    case invalidResponse
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .parsingFailed(let err):
            return "Failed to parse the feed data. \(err.localizedDescription)"
        case .invalidResponse:
            return "Invalid HTTP response."
        case .invalidURL:
            return "The provided URL is invalid."
        }
    }
}

// MARK: - RSSService
final class RSSService {
    
    // MARK: - Public Methods
    
    /// Fetch and parse a feed from a URL
    func fetchAndParseFeed(from url: URL) async throws -> [ParsedArticle] {
        let data = try await fetchFeedData(from: url)
        return try await parseFeed(from: data)
    }
    
    /// Parse a feed from cached/downloaded data
    func parseFeed(from data: Data) async throws -> [ParsedArticle] {
        return try await withCheckedThrowingContinuation { continuation in
            let parser = FeedParser(data: data)
            
            parser.parseAsync { result in
                switch result {
                case .success(let feed):
                    let articles = self.extractArticles(from: feed)
                    continuation.resume(returning: articles)
                    
                case .failure(let error):
                    continuation.resume(throwing: RSSServiceError.parsingFailed(error))
                }
            }
        }
    }
    
    /// Fetch feed data only (for caching purposes)
    func fetchFeedData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("OpenRSS/1.0 (iOS; SwiftUI)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/json, text/xml, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RSSServiceError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw RSSServiceError.invalidResponse
        }

        return data
    }

    
    // MARK: - Private Methods
    
    /// Extract articles from any feed type
    private func extractArticles(from feed: Feed) -> [ParsedArticle] {
        switch feed {
        case .rss(let rss):
            return extractRSS(rss)
        case .atom(let atom):
            return extractAtom(atom)
        case .json(let json):
            return extractJSON(json)
        }
    }
    
    /// Extract articles from RSS feed
    private func extractRSS(_ rss: RSSFeed) -> [ParsedArticle] {
        guard let items = rss.items else { return [] }

        // Channel-level image fallback — used when an individual episode carries no
        // image of its own (the common case for podcast feeds like NPR).
        // Priority: itunes:image href (square podcast artwork) → standard <image> element.
        // Note: RSSFeed has no `media` property in FeedKit, so channel-level
        // media:thumbnail is not accessible here.
        let channelFallbackImage: String? =
            rss.iTunes?.iTunesImage?.attributes?.href ??
            rss.image?.url

        return items.map { item in
            // Get description with fallback to content:encoded
            let description = item.description ?? item.content?.contentEncoded

            // Determine whether the enclosure carries audio so we can exclude it
            // from the image URL slot (an mp3 URL should never feed into AsyncImage).
            let enclosureType = item.enclosure?.attributes?.type ?? ""
            let isAudioEnclosure = Self.isAudioMIMEType(enclosureType)

            // Image priority for each item:
            //   1. itunes:image href  — per-episode artwork (podcasts, some NPR episodes)
            //   2. media:thumbnail    — per-episode wide/square image (e.g. NPR special episodes)
            //   3. media:content      — per-episode media embed (non-audio only)
            //   4. enclosure URL      — only if enclosure is not audio
            var imageURL: String? =
                item.iTunes?.iTunesImage?.attributes?.href ??
                item.media?.mediaThumbnails?.first?.attributes?.url ??
                item.media?.mediaContents?.first(where: {
                    !Self.isAudioMIMEType($0.attributes?.type ?? "") &&
                    ($0.attributes?.medium ?? "") != "audio"
                })?.attributes?.url
            if imageURL == nil && !isAudioEnclosure {
                imageURL = item.enclosure?.attributes?.url
            }

            // Upgrade http:// → https:// for ATS compatibility (e.g. Smashing Magazine
            // enclosures use http:// which iOS blocks in AsyncImage).
            if let url = imageURL, url.hasPrefix("http://") {
                imageURL = "https://" + url.dropFirst(7)
            }

            // If no image came from standard fields, search content:encoded for the
            // first <img src>. Covers feeds like MIT Sloan that embed their lead image
            // directly in the article body HTML without using media:content or enclosure.
            if imageURL == nil {
                imageURL = Self.firstImageURL(in: item.content?.contentEncoded)
            }

            // Final fallback: use the channel-level image (essential for podcast feeds
            // where most episodes carry no per-episode artwork of their own).
            if imageURL == nil {
                imageURL = channelFallbackImage
            }

            // Detect audio enclosure (podcast episodes, audio articles, etc.)
            var audioURL: String? = nil
            if isAudioEnclosure, let url = item.enclosure?.attributes?.url {
                audioURL = url
            }
            if audioURL == nil {
                audioURL = item.media?.mediaContents?.first(where: {
                    Self.isAudioMIMEType($0.attributes?.type ?? "") ||
                    ($0.attributes?.medium ?? "") == "audio"
                })?.attributes?.url
            }

            // Get author
            let author = item.author ?? item.dublinCore?.dcCreator

            return ParsedArticle(
                title: item.title,
                link: item.link,
                publicationDate: item.pubDate,
                description: description,
                imageURL: imageURL,
                author: author,
                audioURL: audioURL
            )
        }
    }

    /// Returns true for any audio/* MIME type commonly found in RSS enclosures.
    private static func isAudioMIMEType(_ type: String) -> Bool {
        type.hasPrefix("audio/")
    }

    /// Finds the first absolute image URL from an `<img src>` attribute in raw HTML.
    /// Handles both double- and single-quoted src values.
    /// Returns nil if no absolute URL (starting with "http") is found.
    private static func firstImageURL(in html: String?) -> String? {
        guard let html else { return nil }
        let pattern = #"<img\b[^>]*?\bsrc=(?:"([^"]+)"|'([^']+)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: nsRange) {
            let srcRange = Range(match.range(at: 1), in: html)
                        ?? Range(match.range(at: 2), in: html)
            guard let srcRange else { continue }
            let candidate = String(html[srcRange])
            if candidate.hasPrefix("http") { return candidate }
        }
        return nil
    }
    
    /// Extract articles from Atom feed
    private func extractAtom(_ atom: AtomFeed) -> [ParsedArticle] {
        guard let entries = atom.entries else { return [] }

        return entries.map { entry in
            // Get the first alternate link (the article URL)
            let link = entry.links?.first(where: { $0.attributes?.rel == "alternate" })?.attributes?.href
                ?? entry.links?.first?.attributes?.href

            // Get content with fallback to summary
            let description = entry.content?.value ?? entry.summary?.value

            // Get publication date
            let date = entry.published ?? entry.updated

            // Get author
            let author = entry.authors?.first?.name

            // Detect audio from enclosure links (e.g. <link rel="enclosure" type="audio/mpeg">)
            // or media:content with audio type/medium.
            var audioURL: String? = entry.links?.first(where: {
                $0.attributes?.rel == "enclosure" &&
                Self.isAudioMIMEType($0.attributes?.type ?? "")
            })?.attributes?.href
            if audioURL == nil {
                audioURL = entry.media?.mediaContents?.first(where: {
                    Self.isAudioMIMEType($0.attributes?.type ?? "") ||
                    ($0.attributes?.medium ?? "") == "audio"
                })?.attributes?.url
            }

            // Get image: prefer media:content (non-audio), then media:thumbnail,
            // then a non-audio enclosure link.
            let imageURL = entry.media?.mediaContents?.first(where: {
                !Self.isAudioMIMEType($0.attributes?.type ?? "") &&
                ($0.attributes?.medium ?? "") != "audio"
            })?.attributes?.url
                ?? entry.media?.mediaThumbnails?.first?.attributes?.url
                ?? entry.links?.first(where: {
                    $0.attributes?.rel == "enclosure" &&
                    !Self.isAudioMIMEType($0.attributes?.type ?? "")
                })?.attributes?.href

            return ParsedArticle(
                title: entry.title,
                link: link,
                publicationDate: date,
                description: description,
                imageURL: imageURL,
                author: author,
                audioURL: audioURL
            )
        }
    }
    
    /// Extract articles from JSON Feed
    private func extractJSON(_ json: JSONFeed) -> [ParsedArticle] {
        guard let items = json.items else { return [] }

        return items.map { item in
            // Get description with preference for HTML content
            let description = item.contentHtml ?? item.contentText ?? item.summary

            // Get image URL
            let imageURL = item.image ?? item.bannerImage

            // Get author
            let author = item.author?.name ?? json.author?.name

            // JSON Feed attachments carry audio files (podcasts commonly use this).
            let audioURL = item.attachments?.first(where: {
                Self.isAudioMIMEType($0.mimeType ?? "")
            })?.url

            return ParsedArticle(
                title: item.title,
                link: item.url,
                publicationDate: item.datePublished,
                description: description,
                imageURL: imageURL,
                author: author,
                audioURL: audioURL
            )
        }
    }
}



