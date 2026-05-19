//
//  AgentEnvelope.swift
//  Payam
//
//  Decodable types matching the /v1/agent response envelope.
//  Each backend tool returns one `AgentView` case; the UI switches on the case
//  and instantiates a typed SwiftUI component — no prose parsing, no string regex.
//

import Foundation

// MARK: - Envelope

struct AgentEnvelope: Decodable {
    let intent: String
    let view: AgentView
    let followups: [String]
    let usage: AgentUsage?
    let quota: AgentQuota?

    enum CodingKeys: String, CodingKey {
        case intent, view, followups, usage, quota
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent    = try c.decodeIfPresent(String.self, forKey: .intent) ?? "unknown"
        view      = try c.decode(AgentView.self, forKey: .view)
        followups = (try? c.decode([String].self, forKey: .followups)) ?? []
        usage     = try? c.decode(AgentUsage.self, forKey: .usage)
        quota     = try? c.decode(AgentQuota.self, forKey: .quota)
    }
}

// MARK: - View Sum Type

/// The payload shape that the iOS UI renders. Drives a `switch` in AgentSheetView
/// over the wire-protocol `type` discriminator.
enum AgentView: Decodable {
    case text(AgentTextPayload)
    case cardList(SourceDiscoveryCardList)
    case ruleCard(FilterRuleCard)
    case triageList(FeedAuditTriage)
    case summaryCard(SummaryCard)
    /// Reached when the server adds a new view type the client doesn't yet know about.
    case unknown(typeName: String)

    private enum CodingKeys: String, CodingKey { case type, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try c.decode(AgentTextPayload.self, forKey: .payload))
        case "card_list":
            self = .cardList(try c.decode(SourceDiscoveryCardList.self, forKey: .payload))
        case "rule_card":
            self = .ruleCard(try c.decode(FilterRuleCard.self, forKey: .payload))
        case "triage_list":
            self = .triageList(try c.decode(FeedAuditTriage.self, forKey: .payload))
        case "summary_card":
            self = .summaryCard(try c.decode(SummaryCard.self, forKey: .payload))
        default:
            self = .unknown(typeName: type)
        }
    }
}

// MARK: - Payload Types

struct AgentTextPayload: Decodable {
    let content: String
}

struct SourceDiscoveryCardList: Decodable {
    let topic: String
    let cards: [Card]
    /// Server-supplied reason when `cards` is empty (e.g. "no catalog match").
    let emptyReason: String?

    struct Card: Decodable, Identifiable {
        var id: String { feedURL }
        let name: String
        let feedURL: String
        let websiteURL: String?
        let oneLine: String
        let sampleHeadlines: [String]
        let why: String?
        let alreadySubscribed: Bool
    }
}

struct FilterRuleCard: Decodable {
    let displayText: String
    let predicate: FilterPredicatePayload
    /// "global" | "folder:<name>" | "feed:<url>"
    let scope: String
    let rationale: String
    let sourceText: String

    struct FilterPredicatePayload: Decodable {
        let keywords: [String]
        let phrases: [String]
        let sourceFeedURLs: [String]
        let contentKinds: [String]
    }
}

/// Phase 2 — empty placeholder so the enum is exhaustive.
struct FeedAuditTriage: Decodable {
    let rows: [Row]
    struct Row: Decodable, Identifiable {
        var id: String { feedURL }
        let feedURL: String
        let title: String
        let suggestion: String  // "remove" | "keep" | "review"
        let reason: String
    }
}

/// Phase 2 — empty placeholder so the enum is exhaustive.
struct SummaryCard: Decodable {
    let title: String
    let bullets: [String]
    let articleURL: String?
}

// MARK: - Usage / Quota

struct AgentUsage: Decodable {
    let model: String?
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
}

struct AgentQuota: Decodable {
    let remaining: Int
    let resetAt: String
}
