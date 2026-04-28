//
//  RiverItem.swift
//  OpenRSS
//
//  Phase 2a — Union type for items displayed in the River feed.
//  Each case carries a different payload; the view switches on the case.
//

import Foundation

// MARK: - RiverItem

enum RiverItem: Identifiable, Hashable, Sendable {
    case article(FeedItem)
    case cluster(ClusterCard)
    case nudge(NudgeCard)
    case digest(DigestCard)

    var id: UUID {
        switch self {
        case .article(let item):   return item.id
        case .cluster(let card):   return card.id
        case .nudge(let card):     return card.id
        case .digest(let card):    return card.id
        }
    }

    /// Positional weight for sort order — higher values appear first.
    /// DigestCards sort near where the first overflow item would have appeared.
    var positionalWeight: Double {
        switch self {
        case .article(let item):   return item.relevanceScore
        case .cluster(let card):   return card.canonicalItem.relevanceScore * 1.1  // slight boost for clusters
        case .nudge:               return 0.95   // nudges float near top
        case .digest(let card):
            // Position digest card based on the insertion time's relative age,
            // scaled to sit slightly below the visible items from the same source.
            let hoursSince = Date().timeIntervalSince(card.insertionPosition) / 3600
            return exp(-0.03 * hoursSince) * 0.5
        }
    }

    /// The relevance score (used for decay-based opacity).
    var relevanceScore: Double {
        switch self {
        case .article(let item):   return item.relevanceScore
        case .cluster(let card):   return card.canonicalItem.relevanceScore
        case .nudge:               return 1.0
        case .digest:              return 0.8   // digest cards always at good opacity
        }
    }
}

// MARK: - RiverSnapshot

/// Immutable snapshot emitted by the pipeline for the view layer.
struct RiverSnapshot: Sendable {
    let items: [RiverItem]
    let generatedAt: Date
    let pipelineDurationMs: Double

    init(items: [RiverItem], generatedAt: Date = Date(), pipelineDurationMs: Double = 0) {
        self.items = items
        self.generatedAt = generatedAt
        self.pipelineDurationMs = pipelineDurationMs
    }
}
