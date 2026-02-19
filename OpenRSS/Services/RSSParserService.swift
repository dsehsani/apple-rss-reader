//
//  RSSParserService.swift
//  OpenRSS
//
//  Phase 1 — Feed Parsing
//
//  Wraps the existing RSSService (FeedKit) and maps results into the
//  pipeline's canonical RSSItem model.  Supports RSS 2.0, Atom, and JSON Feed.
//
//  Usage:
//      let items = try await RSSParserService().fetch(feedURL: url)
//

import Foundation
import FeedKit

// MARK: - Protocol (injectable / testable)

protocol RSSParserServiceProtocol: Sendable {
    /// Fetches and parses a feed URL, returning one `RSSItem` per article.
    func fetch(feedURL: URL) async throws -> [RSSItem]
}

// MARK: - Errors

enum RSSParserError: LocalizedError {
    case networkError(Error)
    case parsingFailed(Error)
    case noItems

    var errorDescription: String? {
        switch self {
        case .networkError(let e):  return "Network error: \(e.localizedDescription)"
        case .parsingFailed(let e): return "Feed parsing failed: \(e.localizedDescription)"
        case .noItems:              return "The feed contained no readable items."
        }
    }
}

// MARK: - RSSParserService

/// Concrete implementation backed by FeedKit.
final class RSSParserService: RSSParserServiceProtocol {

    // Re-use the project's existing network layer
    private let rssService = RSSService()

    // MARK: - Public API

    func fetch(feedURL: URL) async throws -> [RSSItem] {
        let data: Data
        do {
            data = try await rssService.fetchFeedData(from: feedURL)
        } catch {
            throw RSSParserError.networkError(error)
        }
        return try await parseItems(from: data, feedURL: feedURL)
    }

    // MARK: - Private Parsing

    private func parseItems(from data: Data, feedURL: URL) async throws -> [RSSItem] {
        try await withCheckedThrowingContinuation { cont in
            FeedParser(data: data).parseAsync { result in
                switch result {
                case .success(let feed):
                    let items = self.mapItems(feed: feed, feedURL: feedURL)
                    cont.resume(returning: items)
                case .failure(let err):
                    cont.resume(throwing: RSSParserError.parsingFailed(err))
                }
            }
        }
    }

    /// Maps a FeedKit `Feed` (RSS / Atom / JSON) into `[RSSItem]`.
    private func mapItems(feed: Feed, feedURL: URL) -> [RSSItem] {
        switch feed {

        // MARK: RSS 2.0
        case .rss(let rss):
            let feedName = rss.title?.trimmed ?? feedURL.host ?? "Unknown Feed"
            return (rss.items ?? []).compactMap { item in
                guard let title = item.title?.trimmed, !title.isEmpty,
                      let linkStr = item.link,
                      let url = URL(string: linkStr) else { return nil }
                return RSSItem(
                    id: UUID(),
                    title: title,
                    author: item.author ?? item.dublinCore?.dcCreator,
                    publishDate: item.pubDate,
                    summary: item.description ?? item.content?.contentEncoded,
                    sourceURL: url,
                    feedName: feedName
                )
            }

        // MARK: Atom
        case .atom(let atom):
            let feedName = atom.title?.trimmed ?? feedURL.host ?? "Unknown Feed"
            return (atom.entries ?? []).compactMap { entry in
                guard let title = entry.title?.trimmed, !title.isEmpty,
                      let linkStr = entry.links?
                          .first(where: { $0.attributes?.rel == "alternate" })?.attributes?.href
                          ?? entry.links?.first?.attributes?.href,
                      let url = URL(string: linkStr) else { return nil }
                return RSSItem(
                    id: UUID(),
                    title: title,
                    author: entry.authors?.first?.name,
                    publishDate: entry.published ?? entry.updated,
                    summary: entry.content?.value ?? entry.summary?.value,
                    sourceURL: url,
                    feedName: feedName
                )
            }

        // MARK: JSON Feed
        case .json(let json):
            let feedName = json.title?.trimmed ?? feedURL.host ?? "Unknown Feed"
            return (json.items ?? []).compactMap { item in
                guard let title = item.title?.trimmed, !title.isEmpty,
                      let urlStr = item.url,
                      let url = URL(string: urlStr) else { return nil }
                return RSSItem(
                    id: UUID(),
                    title: title,
                    author: item.author?.name ?? json.author?.name,
                    publishDate: item.datePublished,
                    summary: item.contentHtml ?? item.contentText ?? item.summary,
                    sourceURL: url,
                    feedName: feedName
                )
            }
        }
    }
}

// MARK: - Helpers

private extension String {
    /// Strips leading/trailing whitespace and newlines.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
