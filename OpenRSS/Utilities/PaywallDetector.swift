//
//  PaywallDetector.swift
//  OpenRSS
//
//  Heuristic paywall detection. Combines three signals, evaluated cheapest-first
//  and short-circuited on the first positive match:
//    1. Domain allow-list — known subscription-only hosts.
//    2. Body-text phrase scan — subscription prompts embedded in extracted content.
//    3. Truncation signal — very short body ending with an ellipsis / "read more" cue.
//

import Foundation

// MARK: - PaywallDetector

enum PaywallDetector {

    // MARK: - Public API

    /// Returns `true` when the extracted article appears to be behind a paywall.
    /// Cheapest checks run first; the function short-circuits on the first hit.
    static func isPaywalled(article: ExtractedArticle) -> Bool {
        isKnownPaywalledHost(article.sourceURL.host ?? "")
            || bodyContainsPaywallPhrase(in: article.nodes)
            || bodyAppearsAbruptlyTruncated(in: article.nodes)
    }

    /// Convenience overload that runs the domain check only, given a raw URL string.
    /// Useful for a fast pre-extraction hint at ingest time.
    static func isPaywalled(urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host else { return false }
        return isKnownPaywalledHost(host)
    }

    // MARK: - Signal 1: Domain allow-list

    /// Known subscription-only domains. Matching is suffix-based so both
    /// `nytimes.com` and `www.nytimes.com` resolve correctly.
    private static let paywallDomains: Set<String> = [
        "nytimes.com",
        "wsj.com",
        "ft.com",
        "washingtonpost.com",
        "bloomberg.com",
        "theatlantic.com",
        "economist.com",
        "newyorker.com",
        "wired.com",
        "theinformation.com",
        "theathletic.com",
        "latimes.com",
        "seattletimes.com",
        "sfchronicle.com",
        "mercurynews.com",
        "bostonglobe.com",
        "businessinsider.com",
        "barrons.com",
        "medium.com",
        "foreignpolicy.com",
        "hbr.org",
        "thetimes.co.uk",
        "spectator.co.uk",
        "newstatesman.com",
        "technologyreview.com",
    ]

    private static func isKnownPaywalledHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return paywallDomains.contains { lower == $0 || lower.hasSuffix(".\($0)") }
    }

    // MARK: - Signal 2: Body-text phrase scan

    /// Subscription / sign-in prompts that commonly appear in paywalled content.
    private static let paywallPhrases: [String] = [
        "subscribe to continue",
        "subscribers only",
        "subscriber-only",
        "this article is for subscribers",
        "to read the full story",
        "to continue reading",
        "sign in to read",
        "sign in to continue",
        "create an account to continue",
        "free article limit",
        "you've reached your",
        "you have reached your",
        "subscribe to access",
        "subscribe now to read",
        "members only",
        "premium content",
        "support our journalism",
        "already a subscriber",
        "unlock this story",
        "continue reading with a subscription",
        "get unlimited access",
        "this content is available to subscribers",
        "login to read",
        "log in to read",
    ]

    private static func bodyContainsPaywallPhrase(in nodes: [ContentNode]) -> Bool {
        let body = nodes.compactMap { node -> String? in
            switch node {
            case .paragraph(let text):  return text
            case .heading(_, let text): return text
            case .blockquote(let text): return text
            default: return nil
            }
        }.joined(separator: " ").lowercased()

        guard !body.isEmpty else { return false }
        return paywallPhrases.contains { body.contains($0) }
    }

    // MARK: - Signal 3: Truncation signal

    /// Fired only when body word-count is suspiciously low AND the last
    /// paragraph ends with an ellipsis or a common "read more" cue.
    /// Acts as a fallback for sites whose paywall banner Readability swallows
    /// (leaving almost no body text and a dangling sentence).
    private static let truncationWordCountThreshold = 150

    private static func bodyAppearsAbruptlyTruncated(in nodes: [ContentNode]) -> Bool {
        let paragraphs: [String] = nodes.compactMap {
            if case .paragraph(let text) = $0 { return text }
            return nil
        }

        guard !paragraphs.isEmpty else { return false }

        let allWords = paragraphs.joined(separator: " ")
            .split { $0.isWhitespace || $0.isNewline }
        guard allWords.count < truncationWordCountThreshold else { return false }

        let last = paragraphs.last!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return last.hasSuffix("…")
            || last.hasSuffix("...")
            || last.contains("continue reading")
            || last.contains("read more")
    }
}
