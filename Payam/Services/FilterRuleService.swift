//
//  FilterRuleService.swift
//  Payam
//
//  Applies persistent FilterRuleModel rules against feed items during river
//  snapshot assembly. The matcher operates on Sendable FilterRuleSnapshot values
//  so it can run on the background pipeline queue without dragging SwiftData
//  context isolation along.
//

import Foundation
import SwiftData

// MARK: - Content kind heuristics

/// Cheap content-kind detection used by the contentKinds predicate.
/// Intentionally heuristic — the goal is to suppress an obvious genre cluster
/// (opinion, podcast, video, etc.), not perfect classification.
private enum ContentKindDetector {

    static func matches(_ kind: String, item: FeedItem) -> Bool {
        let title = item.title.lowercased()
        let excerpt = item.excerpt.lowercased()
        let link = item.link.absoluteString.lowercased()

        switch kind {
        case "opinion":
            let needles = ["opinion", "op-ed", "op ed", "editorial", "commentary", "/opinion/"]
            return needles.contains(where: { title.contains($0) || excerpt.contains($0) || link.contains($0) })
        case "podcast":
            return item.audioURL != nil || link.contains("/podcast")
        case "video":
            return item.videoURL != nil || link.contains("youtube.com") || link.contains("vimeo.com")
        case "newsletter":
            let needles = ["newsletter", "weekly digest", "this week in"]
            return needles.contains(where: { title.contains($0) || excerpt.contains($0) })
        case "press_release":
            let needles = ["press release", "announces", "today announced", "/newsroom/", "/press/"]
            return needles.contains(where: { title.contains($0) || excerpt.contains($0) || link.contains($0) })
        case "live_blog":
            return title.contains("live blog") || title.contains("live updates") || link.contains("/live/")
        default:
            return false
        }
    }
}

// MARK: - FilterRuleService

enum FilterRuleService {

    /// Loads all enabled filter rules from the SwiftData context and returns them
    /// as Sendable snapshots — safe to hand off to a background queue.
    @MainActor
    static func loadEnabledRuleSnapshots(context: ModelContext) -> [FilterRuleSnapshot] {
        let descriptor = FetchDescriptor<FilterRuleModel>(
            predicate: #Predicate { $0.enabled }
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map { $0.snapshot() }
    }

    /// Returns the matching rule (if any) that would suppress this item.
    /// Scope is honored: a folder-scoped rule only applies when the item's source
    /// belongs to that folder.
    static func matchingRule(
        for item: FeedItem,
        sourceFeedURL: String?,
        sourceFolderName: String?,
        rules: [FilterRuleSnapshot]
    ) -> FilterRuleSnapshot? {
        for rule in rules {
            if !ruleAppliesToScope(rule, sourceFeedURL: sourceFeedURL, sourceFolderName: sourceFolderName) {
                continue
            }
            if predicateMatches(rule.predicate, item: item, sourceFeedURL: sourceFeedURL) {
                return rule
            }
        }
        return nil
    }

    /// Filter a list of items in one pass. Caller supplies a mapping
    /// `sourceID → (feedURL, folderName)` for scope evaluation.
    static func filter(
        items: [FeedItem],
        sourceMap: [UUID: (feedURL: String, folderName: String?)],
        rules: [FilterRuleSnapshot]
    ) -> [FeedItem] {
        guard !rules.isEmpty else { return items }
        return items.filter { item in
            let meta = sourceMap[item.sourceID]
            return matchingRule(
                for: item,
                sourceFeedURL: meta?.feedURL,
                sourceFolderName: meta?.folderName,
                rules: rules
            ) == nil
        }
    }

    // MARK: - Internals

    private static func ruleAppliesToScope(
        _ rule: FilterRuleSnapshot,
        sourceFeedURL: String?,
        sourceFolderName: String?
    ) -> Bool {
        switch rule.scope {
        case .global:
            return true
        case .folder(let name):
            guard let folder = sourceFolderName else { return false }
            return folder.caseInsensitiveCompare(name) == .orderedSame
        case .feed(let url):
            guard let f = sourceFeedURL else { return false }
            return f.caseInsensitiveCompare(url) == .orderedSame
        }
    }

    private static func predicateMatches(
        _ predicate: FilterPredicate,
        item: FeedItem,
        sourceFeedURL: String?
    ) -> Bool {
        if predicate.isEmpty { return false }

        // Source-URL match — exact equality, case-insensitive.
        if let sourceURL = sourceFeedURL {
            for ruleURL in predicate.sourceFeedURLs {
                if ruleURL.caseInsensitiveCompare(sourceURL) == .orderedSame {
                    return true
                }
            }
        }

        // Keyword match — whole-word, case-insensitive across title + excerpt.
        if !predicate.keywords.isEmpty {
            let haystack = "\(item.title) \(item.excerpt)".lowercased()
            for kw in predicate.keywords {
                if containsWholeWord(haystack: haystack, needle: kw.lowercased()) {
                    return true
                }
            }
        }

        // Phrase match — substring, case-insensitive.
        if !predicate.phrases.isEmpty {
            let haystack = "\(item.title) \(item.excerpt)".lowercased()
            for phrase in predicate.phrases {
                if haystack.contains(phrase.lowercased()) {
                    return true
                }
            }
        }

        // Content-kind match.
        for kind in predicate.contentKinds {
            if ContentKindDetector.matches(kind, item: item) {
                return true
            }
        }

        return false
    }

    /// Whole-word containment for keyword matching.
    private static func containsWholeWord(haystack: String, needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return haystack.contains(needle)
        }
        let range = NSRange(haystack.startIndex..., in: haystack)
        return regex.firstMatch(in: haystack, range: range) != nil
    }
}
