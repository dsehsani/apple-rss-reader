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
            // Structural noise — iframes are kept for video embed detection in mapElement
            "script", "style", "noscript",
            // Embed-code blocks — sites show copy-paste embed snippets in <textarea> elements;
            // their content is raw HTML that SwiftSoup surfaces as visible text.
            "textarea",
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

    // MARK: - Logo / icon / avatar image filter

    /// Alt-text keywords that identify branding images (logos, icons, avatars)
    /// that are embedded in article markup but are not editorial content.
    private static let logoKeywords: [String] = [
        "logo", "icon", "avatar", "brand", "badge", "sponsor", "advertiser", "masthead",
        "headshot", "profile photo", "profile picture", "author photo"
    ]

    /// Host substrings for domains that serve user avatars rather than editorial images.
    /// Gravatar (gravatar.com) is the most common — it serves tiny author profile photos
    /// that expand to full-width when rendered with contentMode: .fit in the reader.
    private static let avatarDomains: [String] = [
        "gravatar.com",
        "avatar.githubusercontent.com",
        "pbs.twimg.com/profile_images",
        "secure.gravatar.com"
    ]

    /// Returns true when the alt text indicates the image is a site logo or icon,
    /// not an editorial photograph or illustration.
    private func isLogoAlt(_ alt: String) -> Bool {
        let lower = alt.lowercased()
        return Self.logoKeywords.contains(where: { lower.contains($0) })
    }

    /// Returns true when the image URL points to a known avatar/profile-photo service.
    private func isAvatarURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return Self.avatarDomains.contains(where: { host.contains($0) || "\(host)\(path)".contains($0) })
    }

    // MARK: - Ad-placeholder text filter

    /// Text strings that are pure UI artifacts — never real article content.
    /// All comparisons are exact-match (after lowercasing and trimming), so these
    /// only filter elements whose *entire visible text* is one of these strings.
    private static let adPhrases: Set<String> = [
        // Ad slots
        "advertisement",
        "skip advertisement",
        "skip ad",
        "sponsored",
        "paid content",
        "continue reading below",
        "story continues below advertisement",
        "scroll to continue",
        "content continues below",
        // Video / media player control labels (JS-rendered players captured by Readability)
        "video player is loading",
        "video player is loading.",
        "current time",
        "duration",
        "remaining time",
        "playback rate",
        "loaded: 0%",
        "loaded 0%",
        "stream type live",
        "stream type: live",
        "seek to live",
        "seek to live, currently behind live",
        "seek to live, currently playing live",
        "mute",
        "unmute",
        "fullscreen",
        "quality levels",
        // Podcast / audio player action labels
        "transcript",
        "download",
        "embed",
    ]

    /// Returns true when the text matches a video player label that includes a
    /// numeric value — e.g. "Current Time 0:00", "Duration 1:23", "Loaded: 5%".
    /// Uses prefix+digit matching so "Duration of the summit" is NOT caught.
    private static let videoPlayerArtifactRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(current time|remaining time|duration|playback rate)\s+\d"#
               + #"|^loaded[: ]+\d"#,
        options: .caseInsensitive
    )

    private func isVideoPlayerArtifact(_ text: String) -> Bool {
        guard let regex = Self.videoPlayerArtifactRegex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Returns true when the element's visible text is entity-decoded raw HTML —
    /// e.g. a podcast embed snippet "&lt;iframe src=…&gt;" decoded to "<iframe src=…>".
    private func isRawHTMLText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
    }

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
            // Drop headings that are entity-decoded raw HTML (e.g. embed code snippets)
            guard !isRawHTMLText(text) else { return nil }
            return .heading(level: level, text: text)

        // MARK: Paragraphs
        case "p":
            let text = try plainText(el)
            guard !text.isEmpty, !isAdPlaceholder(text) else { return nil }
            // Drop paragraphs that are video player labels (e.g. "Current Time 0:00")
            // or entity-decoded raw HTML (e.g. podcast embed snippets starting with "<")
            guard !isVideoPlayerArtifact(text), !isRawHTMLText(text) else { return nil }
            return .paragraph(text: text)

        // MARK: Images
        case "img":
            guard let src = try? el.attr("src"), !src.isEmpty,
                  let url = URL(string: src),
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            guard !isAvatarURL(url) else { return nil }
            let alt = (try? el.attr("alt")) ?? ""
            guard !isLogoAlt(alt) else { return nil }
            let caption = alt.isEmpty ? nil : alt
            return .image(url: url, caption: caption)

        // MARK: Figures (may wrap an img + figcaption, or a video iframe)
        case "figure":
            // Video embed inside a figure (common pattern: YouTube wrapped in <figure>)
            if let iframe = try? el.select("iframe").first(),
               let src = try? iframe.attr("src"), !src.isEmpty,
               let url = URL(string: src),
               url.scheme == "https" || url.scheme == "http",
               Self.isVideoHost(url) {
                return .videoEmbed(url: Self.normalizeVideoURL(url), thumbnailURL: Self.videoThumbnail(for: url))
            }
            // Standard image figure
            if let img = try? el.select("img").first(),
               let src = try? img.attr("src"), !src.isEmpty,
               let url = URL(string: src),
               url.scheme == "https" || url.scheme == "http" {
                guard !isAvatarURL(url) else { return nil }
                let alt = (try? img.attr("alt")) ?? ""
                guard !isLogoAlt(alt) else { return nil }
                let caption = (try? el.select("figcaption").first()?.text()) ?? ""
                return .image(url: url, caption: caption.isEmpty ? nil : caption)
            }
            return nil

        // MARK: Video embeds — iframes from known video hosts
        case "iframe":
            guard let src = try? el.attr("src"), !src.isEmpty,
                  let url = URL(string: src),
                  url.scheme == "https" || url.scheme == "http",
                  Self.isVideoHost(url) else { return nil }
            return .videoEmbed(url: Self.normalizeVideoURL(url), thumbnailURL: Self.videoThumbnail(for: url))

        // MARK: HTML5 video elements
        case "video":
            // Try direct src attribute first, then first <source> child
            let srcStr = (try? el.attr("src")) ?? ""
            if !srcStr.isEmpty, let url = URL(string: srcStr),
               url.scheme == "https" || url.scheme == "http" {
                return .videoEmbed(url: url, thumbnailURL: nil)
            }
            if let source = try? el.select("source").first(),
               let src = try? source.attr("src"), !src.isEmpty,
               let url = URL(string: src),
               url.scheme == "https" || url.scheme == "http" {
                return .videoEmbed(url: url, thumbnailURL: nil)
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

        // MARK: Containers — recurse (non-video iframes are treated as opaque containers)
        case "div", "section", "article", "main", "span",
             "details", "summary", "dl", "dt", "dd",
             "tbody", "thead", "tfoot", "iframe":
            return nil  // caller will recurse

        // MARK: Everything else — skip
        default:
            return nil
        }
    }

    // MARK: - Video Helpers

    private static let videoHosts = [
        "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com",
        "bbc.co.uk", "player.bbc.com", "twitch.tv", "rumble.com", "odysee.com"
    ]

    static func isVideoHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return videoHosts.contains(where: { host.contains($0) })
    }

    /// Converts a YouTube embed URL (youtube.com/embed/ID) to a watchable URL.
    static func normalizeVideoURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), host.contains("youtube.com") else { return url }
        let path = url.path
        guard path.contains("/embed/") else { return url }
        let videoID = path
            .components(separatedBy: "/embed/").last?
            .components(separatedBy: "/").first?
            .components(separatedBy: "?").first ?? ""
        guard !videoID.isEmpty,
              let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return url }
        return watchURL
    }

    /// Returns a YouTube thumbnail URL for a YouTube embed URL, nil for other hosts.
    static func videoThumbnail(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host.contains("youtube.com") else { return nil }
        let path = url.path
        guard path.contains("/embed/") else { return nil }
        let videoID = path
            .components(separatedBy: "/embed/").last?
            .components(separatedBy: "/").first?
            .components(separatedBy: "?").first ?? ""
        guard !videoID.isEmpty else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
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
