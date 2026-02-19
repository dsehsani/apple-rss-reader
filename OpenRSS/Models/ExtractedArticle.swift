//
//  ExtractedArticle.swift
//  OpenRSS
//
//  Phase 6 — the fully-processed article that flows from the pipeline
//  into the cache and ultimately into ArticleReaderView.
//

import Foundation

// MARK: - ExtractedArticle

/// A fully-processed article ready for display.  Produced by the pipeline
/// and stored in / retrieved from ArticleCacheService.
struct ExtractedArticle: Identifiable, Sendable {

    /// Stable identifier — matches the source `RSSItem.id` so callers can
    /// look up the cache with the same UUID they have from parsing.
    let id: UUID

    /// Canonical article URL.
    let sourceURL: URL

    /// Reader-mode headline.
    let title: String

    /// Author / byline, if available.
    let author: String?

    /// Publication date from the original feed item.
    let publishDate: Date?

    /// First significant image in the article.
    let heroImageURL: URL?

    /// Human-readable feed/site name.
    let feedName: String

    /// Structured content nodes ready for ArticleReaderView.
    let nodes: [ContentNode]

    /// When this article was cached.
    let cachedAt: Date
}
