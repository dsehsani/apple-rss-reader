//
//  AffinityTracker.swift
//  Payam
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

    /// Steady-state EMA smoothing factor. Higher = recent events weigh more.
    private static let steadyAlpha: Double = 0.15

    /// Returns an event-count-dependent alpha for faster warm-up on new sources.
    /// First 5 events: alpha=0.4 (fast response). Linearly decays to 0.15 by event 20.
    private static func effectiveAlpha(eventCount: Int) -> Double {
        if eventCount < 5 { return 0.4 }
        if eventCount < 20 { return 0.4 - (0.25 * Double(eventCount - 5) / 15.0) }
        return steadyAlpha
    }

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

        let alpha = Self.effectiveAlpha(eventCount: currentCount)
        let updated = alpha * eventWeight + (1.0 - alpha) * currentScore
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
    static func updateAffinity(current: Double, eventWeight: Double, eventCount: Int = 20) -> Double {
        let alpha = effectiveAlpha(eventCount: eventCount)
        let updated = alpha * eventWeight + (1.0 - alpha) * current
        return min(max(updated, -0.3), 1.0)
    }
}
