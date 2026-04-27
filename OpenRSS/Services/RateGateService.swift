//
//  RateGateService.swift
//  OpenRSS
//
//  Phase 2c — Stage 3 of the River pipeline.
//  Runs between clustering (Stage 2) and decay scoring (Stage 4).
//
//  Responsibilities:
//  - Enforce daily slot limits per source based on VelocityTier
//  - Bundle overflow items into DigestCards
//  - Detect flood conditions and emit NudgeCards
//  - Adjust effective limits based on affinity scores
//

import Foundation

// MARK: - RateGateResult

/// Output of the rate gate stage, consumed by the snapshot assembler.
struct RateGateResult: Sendable {
    let digestCards: [DigestCard]
    let nudgeCards: [NudgeCard]
    /// IDs of items that were hidden (river_visible set to false) by the rate gate.
    let hiddenItemIDs: Set<UUID>
}

// MARK: - RateGateService

final class RateGateService: Sendable {

    private let store: SQLiteStore

    init(store: SQLiteStore = .shared) {
        self.store = store
    }

    // MARK: - Public API

    /// Applies rate-gating to all active, river-visible items for the current calendar day.
    ///
    /// - Returns: A `RateGateResult` containing digest cards, nudge cards, and hidden item IDs.
    func applyRateGate() -> RateGateResult {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        // Fetch all active river-visible items
        let allItems = store.fetchRiverItems()

        // Group items by source
        var itemsBySource: [UUID: [FeedItem]] = [:]
        for item in allItems {
            itemsBySource[item.sourceID, default: []].append(item)
        }

        var digestCards: [DigestCard] = []
        var nudgeCards: [NudgeCard] = []
        var hiddenItemIDs = Set<UUID>()

        for (sourceID, items) in itemsBySource {
            // Filter to items from the current calendar day
            let todayItems = items.filter { $0.fetchedAt >= startOfDay }
                .sorted { $0.publishedAt < $1.publishedAt }

            guard !todayItems.isEmpty else { continue }

            // Determine effective slot limit
            let velocityTier = todayItems.first?.velocityTier ?? .article
            let defaultLimit = velocityTier.defaultSlotLimit
            let effectiveLimit = computeEffectiveLimit(
                defaultLimit: defaultLimit,
                sourceID: sourceID
            )

            // Apply slot limit — items beyond the limit become overflow
            if todayItems.count > effectiveLimit && effectiveLimit < Int.max {
                let visibleItems = Array(todayItems.prefix(effectiveLimit))
                let overflowItems = Array(todayItems.dropFirst(effectiveLimit))

                // Mark overflow items as hidden
                let overflowIDs = overflowItems.map(\.id)
                hiddenItemIDs.formUnion(overflowIDs)

                // Extract highlights (2-3 title snippets from overflow)
                let highlights = Array(overflowItems.prefix(3).map(\.title))

                // Resolve source name
                let sourceName = resolveSourceName(sourceID: sourceID)

                // insertionPosition = timestamp of first overflow item
                let insertionPosition = overflowItems.first?.publishedAt ?? now

                let digest = DigestCard(
                    sourceID: sourceID,
                    sourceName: sourceName,
                    itemCount: overflowItems.count,
                    highlights: highlights,
                    overflowIDs: overflowIDs,
                    overflowItems: overflowItems,
                    insertionPosition: insertionPosition
                )
                digestCards.append(digest)

                _ = visibleItems // kept visible, no action needed
            }

            // Flood detection: check rolling 2-hour window
            let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
            let recentItems = items.filter { $0.publishedAt >= twoHoursAgo }
            let recentCount = recentItems.count

            if recentCount > 0 {
                let isFlood = detectFlood(
                    sourceID: sourceID,
                    recentCount: recentCount
                )
                if isFlood {
                    let sourceName = resolveSourceName(sourceID: sourceID)
                    let nudge = NudgeCard(
                        sourceID: sourceID,
                        sourceName: sourceName,
                        itemCount: recentCount,
                        message: "\(sourceName) posted \(recentCount) articles in the last 2 hours"
                    )
                    nudgeCards.append(nudge)
                }
            }
        }

        // Persist visibility changes to SQLite
        if !hiddenItemIDs.isEmpty {
            store.setRiverVisible(false, forItemIDs: Array(hiddenItemIDs))
        }

        return RateGateResult(
            digestCards: digestCards,
            nudgeCards: nudgeCards,
            hiddenItemIDs: hiddenItemIDs
        )
    }

    // MARK: - Effective Limit Computation

    /// Adjusts the default slot limit based on the source's affinity score.
    private func computeEffectiveLimit(defaultLimit: Int, sourceID: UUID) -> Int {
        guard defaultLimit < Int.max else { return Int.max }

        let affinity = store.fetchAffinity(forSource: sourceID)
        let affinityScore = affinity?.affinityScore ?? 0.0

        if affinityScore > 0.7 {
            // Boost: min(defaultLimit * 1.5, defaultLimit + 3)
            let boosted = min(
                Int(Double(defaultLimit) * 1.5),
                defaultLimit + 3
            )
            return boosted
        } else if affinityScore < -0.15 {
            // Reduce: max(1, defaultLimit - 2)
            return max(1, defaultLimit - 2)
        }

        return defaultLimit
    }

    // MARK: - Flood Detection

    /// Detects if a source is flooding: recent count > mean + 3 sigma of historical baseline.
    ///
    /// Historical baseline is computed from the source's item counts per 2-hour windows
    /// over the last 7 days.
    private func detectFlood(sourceID: UUID, recentCount: Int) -> Bool {
        let historicalCounts = store.fetchHistoricalItemCounts(
            forSource: sourceID,
            windowHours: 2,
            lookbackDays: 7
        )

        guard historicalCounts.count >= 3 else {
            // Not enough data to establish baseline — skip flood detection
            return false
        }

        let mean = historicalCounts.reduce(0.0) { $0 + Double($1) } / Double(historicalCounts.count)
        let variance = historicalCounts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(historicalCounts.count)
        let sigma = sqrt(variance)

        // Flood if recent count > mean + 3 sigma (minimum threshold of 5 to avoid false positives)
        let threshold = max(mean + 3.0 * sigma, 5.0)
        return Double(recentCount) > threshold
    }

    // MARK: - Source Name Resolution

    /// Resolves the human-readable name for a source.
    /// Falls back to "Unknown Source" if the source can't be found.
    private func resolveSourceName(sourceID: UUID) -> String {
        // Try to get from affinity record first (has source metadata)
        if let affinity = store.fetchAffinity(forSource: sourceID) {
            _ = affinity // affinity record doesn't store names
        }
        // Source names are resolved by the ViewModel layer via FeedDataService.
        // Use UUID string as placeholder — the ViewModel will resolve it.
        return sourceID.uuidString
    }
}
