//
//  ReadableContent.swift
//  OpenRSS
//
//  Phase 3 — the output produced by ReadabilityExtractionService.
//  Contains the reader-mode extracted content ready for Phase 4 normalization.
//

import Foundation

// MARK: - ReadableContent

/// Reader-mode content extracted from raw HTML via Mozilla Readability.js.
struct ReadableContent: Sendable {

    /// Article headline (may differ from RSS feed title).
    let title: String

    /// Byline / author string extracted by Readability.
    let byline: String?

    /// Cleaned HTML string — scripts, ads, and navigation stripped.
    let content: String

    /// Short excerpt / lede.
    let excerpt: String?

    /// First significant image found in the article, if any.
    let heroImageURL: URL?
}
