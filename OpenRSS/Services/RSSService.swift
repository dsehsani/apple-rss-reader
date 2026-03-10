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

        return items.map { item in
            // Get description with fallback to content:encoded
            let description = item.description ?? item.content?.contentEncoded

            // Get image URL from media:content or enclosure.
            // Upgrade http:// → https:// for ATS compatibility (e.g. Smashing Magazine
            // enclosures use http:// which iOS blocks in AsyncImage).
            var imageURL = item.media?.mediaContents?.first?.attributes?.url
                ?? item.enclosure?.attributes?.url
            if let url = imageURL, url.hasPrefix("http://") {
                imageURL = "https://" + url.dropFirst(7)
            }

            // If no image came from standard fields, search content:encoded for the
            // first <img src>. Covers feeds like MIT Sloan that embed their lead image
            // directly in the article body HTML without using media:content or enclosure.
            if imageURL == nil {
                imageURL = Self.firstImageURL(in: item.content?.contentEncoded)
            }

            // Get author
            let author = item.author ?? item.dublinCore?.dcCreator

            return ParsedArticle(
                title: item.title,
                link: item.link,
                publicationDate: item.pubDate,
                description: description,
                imageURL: imageURL,
                author: author
            )
        }
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
            
            // Get image: prefer media:content (used by The Atlantic, many Atom feeds),
            // then media:thumbnail, then an enclosure link.
            let imageURL = entry.media?.mediaContents?.first?.attributes?.url
                ?? entry.media?.mediaThumbnails?.first?.attributes?.url
                ?? entry.links?.first(where: { $0.attributes?.rel == "enclosure" })?.attributes?.href
            
            return ParsedArticle(
                title: entry.title,
                link: link,
                publicationDate: date,
                description: description,
                imageURL: imageURL,
                author: author
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
            
            return ParsedArticle(
                title: item.title,
                link: item.url,
                publicationDate: item.datePublished,
                description: description,
                imageURL: imageURL,
                author: author
            )
        }
    }
}



