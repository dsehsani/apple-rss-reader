//
//  VelocityTier.swift
//  OpenRSS
//
//  Classifies feed posting frequency to determine decay half-life.
//

import Foundation

enum VelocityTier: String, Codable, CaseIterable {
    case burst      // >2 posts/day average
    case daily      // 0.5–2 posts/day
    case weekly     // 1–3 posts/week
    case slow       // <1 post/week

    var halfLifeHours: Double {
        switch self {
        case .burst:  return 18
        case .daily:  return 36
        case .weekly: return 72
        case .slow:   return 168
        }
    }

    var displayName: String {
        switch self {
        case .burst:  return "Burst"
        case .daily:  return "Daily"
        case .weekly: return "Weekly"
        case .slow:   return "Slow"
        }
    }

    var shortDescription: String {
        switch self {
        case .burst:  return "18h"
        case .daily:  return "36h"
        case .weekly: return "72h"
        case .slow:   return "7 days"
        }
    }

    /// Infers the velocity tier from a post-per-day rate.
    static func from(postsPerDay: Double) -> VelocityTier {
        if postsPerDay > 2.0 { return .burst }
        if postsPerDay >= 0.5 { return .daily }
        if postsPerDay >= 0.14 { return .weekly }
        return .slow
    }
}
