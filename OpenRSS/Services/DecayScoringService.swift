//
//  DecayScoringService.swift
//  OpenRSS
//
//  Phase 2a — Stage 4 of the River Pipeline.
//  Computes time-based relevance decay for each feed item using
//  exponential decay with velocity-tier-specific half-lives.
//  Optionally boosts scores based on source affinity (Phase 2d).
//

import Foundation

// MARK: - DecayScoringService

final class DecayScoringService: Sendable {

    private let store = SQLiteStore.shared

    // MARK: - Relevance Thresholds

    /// Items above this threshold are shown at full opacity.
    static let fullOpacityThreshold: Double = 0.7

    /// Items between this and fullOpacity are shown at 60% opacity.
    static let mediumOpacityThreshold: Double = 0.4

    /// Items between this and mediumOpacity are shown at 35% opacity.
    static let lowOpacityThreshold: Double = 0.2

    /// Items below this threshold are aged out (archived).
    static let agedOutThreshold: Double = 0.2

    // MARK: - Public API

    /// Scores all active items and updates their relevance in SQLite.
    /// Returns the number of items that were newly aged out.
    @discardableResult
    func scoreAllItems() -> Int {
        let items = store.fetchAllActiveItems()
        let now = Date()
        var agedOutCount = 0

        var updates: [(id: UUID, relevanceScore: Double, agedOut: Bool)] = []

        for item in items {
            let hoursSince = now.timeIntervalSince(item.publishedAt) / 3600
            let rawRelevance = Self.relevance(hoursSincePublished: hoursSince, tier: item.velocityTier)

            // Apply affinity boost (if available)
            let boost = affinityBoost(for: item.sourceID)
            let adjustedRelevance = rawRelevance * (1.0 + boost)

            let shouldAge = adjustedRelevance < Self.agedOutThreshold
            if shouldAge && !item.agedOut {
                agedOutCount += 1
            }

            updates.append((
                id: item.id,
                relevanceScore: adjustedRelevance,
                agedOut: shouldAge
            ))
        }

        store.updateScores(updates)
        return agedOutCount
    }

    // MARK: - Decay Formula

    /// Exponential decay: relevance = e^(-lambda * t)
    /// where lambda = ln(2) / halfLifeHours.
    static func relevance(hoursSincePublished t: Double, tier: VelocityTier) -> Double {
        exp(-tier.lambda * t)
    }

    // MARK: - Opacity Mapping

    /// Maps a relevance score to an opacity value for the UI.
    /// Floor of 0.7 so cards always remain clearly readable.
    static func opacity(for relevanceScore: Double) -> Double {
        switch relevanceScore {
        case fullOpacityThreshold...:
            return 1.0
        case mediumOpacityThreshold..<fullOpacityThreshold:
            return 0.85
        default:
            return 0.7
        }
    }

    /// Maps a relevance score to a font-size scale factor.
    static func fontScale(for relevanceScore: Double) -> Double {
        return 1.0
    }

    // MARK: - Affinity Boost

    /// Returns the affinity boost for a source, clamped to [0, 0.5].
    private func affinityBoost(for sourceID: UUID) -> Double {
        guard let record = store.fetchAffinity(forSource: sourceID) else { return 0 }
        return min(max(record.affinityScore, 0), 0.5)
    }
}
