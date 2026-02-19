//
//  ContentNormalizerService.swift
//  OpenRSS
//
//  Phase 4 — Content Normalization
//
//  Parses the cleaned HTML produced by ReadabilityExtractionService and
//  converts it into a typed [ContentNode] array for rendering in Phase 5.
//
//  Approach:
//  - Uses SwiftSoup to walk the DOM
//  - Maps standard HTML elements to ContentNode cases
//  - Strips scripts, styles, ads, and other non-content tags
//  - Preserves inline links as plain-text (URLs embedded in parentheses)
//

import Foundation
import SwiftSoup

// MARK: - Protocol

protocol ContentNormalizerServiceProtocol: Sendable {
    func normalize(content: ReadableContent) throws -> [ContentNode]
}

// MARK: - Errors

enum ContentNormalizerError: LocalizedError {
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let msg):
            return "Failed to parse article HTML: \(msg)"
        }
    }
}

// MARK: - ContentNormalizerService

final class ContentNormalizerService: ContentNormalizerServiceProtocol {

    // MARK: - Public API

    func normalize(content: ReadableContent) throws -> [ContentNode] {
        do {
            let doc = try SwiftSoup.parseBodyFragment(content.content)
            stripNoise(from: doc)
            return try extractNodes(from: doc.body() ?? doc)
        } catch let error as ContentNormalizerError {
            throw error
        } catch {
            throw ContentNormalizerError.parseFailure(error.localizedDescription)
        }
    }

    // MARK: - Noise Removal

    /// Removes non-content elements that Readability may have missed.
    ///
    /// Rules:
    /// - Only script/style/iframe are removed by tag name (safe, never content).
    /// - Ad containers are targeted by exact attribute matches or well-known
    ///   aria labels — NOT by [class*='ad'] substring which matches "loaded",
    ///   "lead", "upload", etc. and nukes legitimate content.
    private func stripNoise(from doc: Document) {
        let selectors: [String] = [
            // Structural noise
            "script", "style", "noscript", "iframe",
            // Ad slots by role / aria label (exact, not substring)
            "[aria-label='advertisement']",
            "[aria-label='Advertisement']",
            "[data-ad-unit]",
            "[data-ad-slot]",
            "[data-google-query-id]",
            // NYT-specific ad wrappers
            "[class='ad']",
            "[id='ad']",
            "[class='AdWrapper']",
            "[class='adslot']",
            // Generic injected ad containers
            "ins.adsbygoogle",
            "[data-testid='ad-container']",
            "[data-testid='Advertisement']"
        ]
        for selector in selectors {
            if let elements = try? doc.select(selector) {
                elements.forEach { try? $0.remove() }
            }
        }
    }

    // MARK: - Ad-placeholder text filter

    /// Text strings that are pure ad artifacts — never real article content.
    private static let adPhrases: Set<String> = [
        "advertisement",
        "skip advertisement",
        "skip ad",
        "sponsored",
        "paid content",
        "continue reading below",
        "story continues below advertisement",
        "scroll to continue",
        "content continues below"
    ]

    /// Returns true if the entire text of an element is an ad placeholder.
    private func isAdPlaceholder(_ text: String) -> Bool {
        Self.adPhrases.contains(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Node Extraction

    private func extractNodes(from element: Element) throws -> [ContentNode] {
        var nodes: [ContentNode] = []

        for child in element.children() {
            if let node = try mapElement(child) {
                nodes.append(node)
            } else {
                // Recurse into containers (div, section, article, etc.)
                nodes += try extractNodes(from: child)
            }
        }

        return nodes
    }

    /// Maps a single element to a ContentNode, or returns nil if this
    /// element is a container that should be recursed into.
    private func mapElement(_ el: Element) throws -> ContentNode? {
        let tag = el.tagName().lowercased()

        switch tag {

        // MARK: Headings
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 2
            let text = try plainText(el)
            guard !text.isEmpty, !isAdPlaceholder(text) else { return nil }
            return .heading(level: level, text: text)

        // MARK: Paragraphs
        case "p":
            let text = try plainText(el)
            guard !text.isEmpty, !isAdPlaceholder(text) else { return nil }
            return .paragraph(text: text)

        // MARK: Images
        case "img":
            guard let src = try? el.attr("src"), !src.isEmpty,
                  let url = URL(string: src) else { return nil }
            let alt = (try? el.attr("alt")) ?? ""
            let caption = alt.isEmpty ? nil : alt
            return .image(url: url, caption: caption)

        // MARK: Figures (may wrap an img + figcaption)
        case "figure":
            if let img = try? el.select("img").first(),
               let src = try? img.attr("src"), !src.isEmpty,
               let url = URL(string: src) {
                let caption = (try? el.select("figcaption").first()?.text()) ?? ""
                return .image(url: url, caption: caption.isEmpty ? nil : caption)
            }
            return nil

        // MARK: Blockquotes
        case "blockquote":
            let text = try plainText(el)
            guard !text.isEmpty, !isAdPlaceholder(text) else { return nil }
            return .blockquote(text: text)

        // MARK: Lists
        case "ul":
            let items = try listItems(el)
            guard !items.isEmpty else { return nil }
            return .list(items: items, ordered: false)

        case "ol":
            let items = try listItems(el)
            guard !items.isEmpty else { return nil }
            return .list(items: items, ordered: true)

        // MARK: Code
        case "pre":
            let codeEl = (try? el.select("code").first()) ?? el
            let text = (try? codeEl.text()) ?? ""
            guard !text.isEmpty else { return nil }
            return .codeBlock(text: text)

        case "code":
            // Inline code — treat as a paragraph if it's at the top level
            let text = (try? el.text()) ?? ""
            guard !text.isEmpty else { return nil }
            return .codeBlock(text: text)

        // MARK: Tables
        case "table":
            return try parseTable(el)

        // MARK: Containers — recurse
        case "div", "section", "article", "main", "span",
             "details", "summary", "dl", "dt", "dd",
             "tbody", "thead", "tfoot":
            return nil  // caller will recurse

        // MARK: Everything else — skip
        default:
            return nil
        }
    }

    // MARK: - Table Parsing

    private func parseTable(_ el: Element) throws -> ContentNode? {
        // Extract header cells from <th> elements (first row or <thead>)
        let headers: [String] = (try? el.select("th").array()
            .map { (try? $0.text()) ?? "" }
            .filter { !$0.isEmpty }) ?? []

        // Extract data rows — <tr> rows that contain <td> cells
        let rows: [[String]] = (try? el.select("tr").array().compactMap { tr -> [String]? in
            let cells = (try? tr.select("td").array().map { (try? $0.text()) ?? "" }) ?? []
            // Skip rows that are empty or all-whitespace
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return trimmed.allSatisfy({ $0.isEmpty }) ? nil : trimmed
        }) ?? []

        guard !headers.isEmpty || !rows.isEmpty else { return nil }
        return .table(headers: headers, rows: rows)
    }

    // MARK: - Text Helpers

    /// Returns raw `.text()` with whitespace normalised.
    private func plainText(_ el: Element) throws -> String {
        (try? el.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Returns text with inline `<a href>` links appended as " (URL)".
    private func inlineText(_ el: Element) throws -> String {
        var result = ""
        for node in el.getChildNodes() {
            if let textNode = node as? TextNode {
                result += textNode.text()
            } else if let element = node as? Element {
                let inner = (try? element.text()) ?? ""
                if element.tagName() == "a",
                   let href = try? element.attr("href"),
                   !href.isEmpty,
                   URL(string: href) != nil {
                    result += inner + " (\(href))"
                } else {
                    result += inner
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts text from each `<li>` child of a list element.
    private func listItems(_ el: Element) throws -> [String] {
        try el.select("li").compactMap { li in
            let text = (try? li.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
    }
}
