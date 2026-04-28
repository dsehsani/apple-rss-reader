//
//  AffinityTracker.swift
//  OpenRSS
//
//  Phase 2d — Singleton that records user interaction events and updates
//  per-source affinity scores using an Exponential Moving Average (EMA).
//
//  All data is LOCAL ONLY. No sync, no analytics, no external services.
//

import Foundation

// MARK: - AffinityTracker

final class AffinityTracker: Sendable {

    // MARK: - Singleton

    static let shared = AffinityTracker()

    // MARK: - Constants

    /// EMA smoothing factor. Higher = recent events weigh more.
    private static let alpha: Double = 0.15

    // MARK: - Dependencies

    private let store: SQLiteStore

    // MARK: - Init

    private init(store: SQLiteStore = .shared) {
        self.store = store
    }

    // MARK: - Public API

    /// Records an interaction event and asynchronously updates the source's affinity score.
    ///
    /// - Parameters:
    ///   - eventType: The type of interaction that occurred.
    ///   - sourceID: The source associated with the interaction.
    ///   - itemID: The feed item associated with the interaction.
    ///   - dwellTime: Optional dwell time in seconds (for dwell-based events).
    func record(
        _ eventType: InteractionEventType,
        sourceID: UUID,
        itemID: UUID,
        dwellTime: TimeInterval? = nil
    ) {
        let event = InteractionEvent(
            sourceID: sourceID,
            itemID: itemID,
            eventType: eventType,
            dwellTime: dwellTime
        )

        // Persist the event
        store.insertEvent(event)

        // Update affinity asynchronously
        DispatchQueue.global(qos: .utility).async { [self] in
            updateAffinityScore(for: sourceID, eventWeight: eventType.weight)
        }
    }

    // MARK: - EMA Update

    /// Computes the new affinity score using EMA and persists it.
    ///
    /// Formula: updated = alpha * eventWeight + (1 - alpha) * current
    /// Clamped to [-0.3, 1.0].
    private func updateAffinityScore(for sourceID: UUID, eventWeight: Double) {
        let existing = store.fetchAffinity(forSource: sourceID)
        let currentScore = existing?.affinityScore ?? 0.0
        let currentCount = existing?.eventCount ?? 0
        let velocityTier = existing?.velocityTier ?? .article
        let slotLimit = existing?.slotLimit ?? velocityTier.defaultSlotLimit

        let updated = Self.alpha * eventWeight + (1.0 - Self.alpha) * currentScore
        let clamped = min(max(updated, -0.3), 1.0)

        let record = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: clamped,
            eventCount: currentCount + 1,
            lastUpdated: Date(),
            velocityTier: velocityTier,
            slotLimit: slotLimit
        )

        store.upsertAffinity(record)
    }

    // MARK: - Utility

    /// Pure function for computing EMA (useful for testing).
    static func updateAffinity(current: Double, eventWeight: Double) -> Double {
        let updated = alpha * eventWeight + (1.0 - alpha) * current
        return min(max(updated, -0.3), 1.0)
    }
}
