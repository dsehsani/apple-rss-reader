//
//  FilterRuleModel.swift
//  Payam
//
//  SwiftData persistent model for an AI-generated (or hand-edited) filter rule.
//  Rules apply during river snapshot assembly to suppress matching items.
//
//  The predicate is stored as a JSON string under the hood so the model schema
//  stays stable while the predicate shape evolves. Typed accessors are exposed
//  via `predicate` and `scope` computed properties.
//

import Foundation
import SwiftData

// MARK: - Value Types (Codable, not persisted directly)

struct FilterPredicate: Codable, Equatable, Sendable {
    var keywords: [String]
    var phrases: [String]
    var sourceFeedURLs: [String]
    var contentKinds: [String]

    static let empty = FilterPredicate(
        keywords: [], phrases: [], sourceFeedURLs: [], contentKinds: []
    )

    var isEmpty: Bool {
        keywords.isEmpty && phrases.isEmpty && sourceFeedURLs.isEmpty && contentKinds.isEmpty
    }
}

enum FilterScope: Equatable, Sendable {
    case global
    case folder(name: String)
    case feed(url: String)

    var raw: String {
        switch self {
        case .global:                return "global"
        case .folder(let name):      return "folder:\(name)"
        case .feed(let url):         return "feed:\(url)"
        }
    }

    init(raw: String) {
        if raw.hasPrefix("folder:") {
            self = .folder(name: String(raw.dropFirst("folder:".count)))
        } else if raw.hasPrefix("feed:") {
            self = .feed(url: String(raw.dropFirst("feed:".count)))
        } else {
            self = .global
        }
    }
}

// MARK: - SwiftData @Model

@Model
final class FilterRuleModel {

    /// Stable identity for the rule.
    var id: UUID

    /// User-facing label ("Hide opinion pieces").
    var displayText: String

    /// JSON-encoded `FilterPredicate`. See `predicate` for the typed accessor.
    var predicateJSON: String

    /// Raw scope token; see `scope` for the typed accessor.
    /// "global" | "folder:<name>" | "feed:<url>"
    var scopeRaw: String

    /// One-line explanation surfaced in the rule card and Settings list.
    var rationale: String

    /// Verbatim user message that produced this rule. Useful for "explain why"
    /// and lets us re-parse with a newer model if the schema evolves.
    var sourceText: String

    /// Whether the rule is active. Toggled from Settings.
    var enabled: Bool

    /// Creation timestamp — used for sort order and stale-rule cleanup.
    var createdAt: Date

    /// "agent" when produced by parse_filter_rule; "manual" when authored by hand.
    var createdBy: String

    // MARK: - Computed accessors

    var predicate: FilterPredicate {
        get {
            guard let data = predicateJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(FilterPredicate.self, from: data)
            else { return .empty }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                predicateJSON = str
            }
        }
    }

    var scope: FilterScope {
        get { FilterScope(raw: scopeRaw) }
        set { scopeRaw = newValue.raw }
    }

    // MARK: - Init

    init(
        displayText: String,
        predicate: FilterPredicate,
        scope: FilterScope = .global,
        rationale: String = "",
        sourceText: String = "",
        createdBy: String = "agent"
    ) {
        self.id = UUID()
        self.displayText = displayText
        self.predicateJSON = {
            (try? JSONEncoder().encode(predicate))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }()
        self.scopeRaw = scope.raw
        self.rationale = rationale
        self.sourceText = sourceText
        self.enabled = true
        self.createdAt = Date()
        self.createdBy = createdBy
    }

    /// Snapshot the rule into a Sendable value type. SwiftData @Model classes
    /// must stay on their owning context's actor; the snapshot is what the
    /// river pipeline carries across the background-queue boundary.
    func snapshot() -> FilterRuleSnapshot {
        FilterRuleSnapshot(
            id: id,
            displayText: displayText,
            predicate: predicate,
            scope: scope
        )
    }
}

// MARK: - Sendable snapshot

/// Cross-actor representation of a filter rule. Read by `FilterRuleService.filter`
/// from any queue. Created via `FilterRuleModel.snapshot()` on MainActor.
struct FilterRuleSnapshot: Sendable, Identifiable {
    let id: UUID
    let displayText: String
    let predicate: FilterPredicate
    let scope: FilterScope
}
