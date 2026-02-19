//
//  ContentNode.swift
//  OpenRSS
//
//  Phase 4 — the typed DOM representation produced by ContentNormalizerService.
//  Each case maps one-to-one to a dedicated sub-view in Phase 5.
//

import Foundation

// MARK: - ContentNode

/// A single semantic unit of article content.
enum ContentNode: Codable, Sendable {

    /// A section heading.
    case heading(level: Int, text: String)

    /// A body paragraph (may contain inline links).
    case paragraph(text: String)

    /// An image with an optional caption.
    case image(url: URL, caption: String?)

    /// A pulled quote or block-level quotation.
    case blockquote(text: String)

    /// An ordered or unordered list.
    case list(items: [String], ordered: Bool)

    /// A preformatted code block.
    case codeBlock(text: String)

    /// A data table with an optional header row and data rows.
    case table(headers: [String], rows: [[String]])
}
