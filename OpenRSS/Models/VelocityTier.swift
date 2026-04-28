//
//  VelocityTier.swift
//  OpenRSS
//
//  Phase 2a — Velocity tier classification for feed items.
//  Each tier has a different half-life controlling how quickly
//  items decay in relevance.
//

import Foundation

// MARK: - VelocityTier

enum VelocityTier: String, Codable, CaseIterable, Sendable {
    case breaking
    case news
    case article
    case essay
    case evergreen

    /// Half-life in hours — after this many hours the item's relevance drops to 50%.
    var halfLifeHours: Double {
        switch self {
        case .breaking:  return 3
        case .news:      return 18
        case .article:   return 48
        case .essay:     return 168
        case .evergreen: return 720
        }
    }

    /// Exponential decay constant: lambda = ln(2) / halfLife.
    var lambda: Double { log(2) / halfLifeHours }

    /// Default daily slot limit for rate-gating per source.
    var defaultSlotLimit: Int {
        switch self {
        case .breaking:  return 3
        case .news:      return 5
        case .article:   return 8
        case .essay:     return .max   // unlimited
        case .evergreen: return 2
        }
    }

    /// Short half-life description for headers.
    var shortDescription: String {
        switch self {
        case .breaking:  return "3h"
        case .news:      return "18h"
        case .article:   return "48h"
        case .essay:     return "7 days"
        case .evergreen: return "30 days"
        }
    }

    /// Human-readable label for settings UI.
    var displayName: String {
        switch self {
        case .breaking:  return "Breaking News"
        case .news:      return "General News"
        case .article:   return "Articles / Blogs"
        case .essay:     return "Essays / Newsletters"
        case .evergreen: return "Evergreen / Podcasts"
        }
    }
}

// MARK: - Heuristic Assignment

extension VelocityTier {

    /// Assigns a velocity tier based on the average publish frequency of a source.
    ///
    /// - Parameter averageItemsPerDay: Rolling average of items published per day.
    /// - Returns: The inferred velocity tier.
    static func infer(averageItemsPerDay: Double) -> VelocityTier {
        switch averageItemsPerDay {
        case 20...:        return .breaking    // Wire services, breaking-news feeds
        case 5..<20:       return .news        // General news outlets
        case 1..<5:        return .article     // Tech blogs, topic blogs
        case 0.1..<1:      return .essay       // Weekly newsletters, personal blogs
        default:           return .evergreen   // Monthly or less frequent
        }
    }
}
