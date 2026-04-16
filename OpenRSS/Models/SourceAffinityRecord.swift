//
//  SourceAffinityRecord.swift
//  OpenRSS
//
//  Phase 2a — Per-source affinity record.
//  Persisted in the source_affinity SQLite table.
//  The affinity score is updated via EMA in Phase 2d;
//  for now the record is created with neutral defaults.
//

import Foundation

// MARK: - SourceAffinityRecord

struct SourceAffinityRecord: Sendable {
    let sourceID: UUID
    var affinityScore: Double   // clamped [-0.3, 1.0]
    var eventCount: Int
    var lastUpdated: Date
    var velocityTier: VelocityTier
    var slotLimit: Int

    init(
        sourceID: UUID,
        affinityScore: Double = 0.0,
        eventCount: Int = 0,
        lastUpdated: Date = Date(),
        velocityTier: VelocityTier = .article,
        slotLimit: Int = 8
    ) {
        self.sourceID = sourceID
        self.affinityScore = min(max(affinityScore, -0.3), 1.0)
        self.eventCount = eventCount
        self.lastUpdated = lastUpdated
        self.velocityTier = velocityTier
        self.slotLimit = slotLimit
    }

    /// Human-readable affinity label for the Settings UI.
    var affinityLabel: String {
        switch affinityScore {
        case ..<0:        return "Low"
        case 0..<0.3:     return "Neutral"
        case 0.3..<0.7:   return "Interested"
        default:          return "Highly Interested"
        }
    }
}
