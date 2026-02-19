//
//  RSSItem.swift
//  OpenRSS
//
//  Phase 1 — the canonical domain model produced by RSSParserService.
//  Every field in the pipeline (content fetch, extraction, caching) flows
//  from this struct.
//

import Foundation

// MARK: - RSSItem

/// A single article item parsed from an RSS, Atom, or JSON feed.
struct RSSItem: Identifiable, Hashable, Sendable {

    /// Stable per-session identifier (not persisted; cache uses sourceURL as key).
    let id: UUID

    /// The article headline.
    let title: String

    /// Byline from the feed, if present.
    let author: String?

    /// Publication date from the feed, if present.
    let publishDate: Date?

    /// Raw summary / description from the feed (may contain HTML).
    let summary: String?

    /// Canonical URL of the full article page — used by Phase 2 to fetch HTML.
    let sourceURL: URL

    /// Human-readable name of the feed channel (e.g. "TechCrunch").
    let feedName: String
}
