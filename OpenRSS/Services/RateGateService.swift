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

    /// Applies rate-gating across the full retention window.
    ///
    /// This method is idempotent: every run re-evaluates ALL non-aged-out items
    /// (not just today's) and writes the correct `river_visible` value for each,
    /// restoring previously hidden items when slot limits have changed.
    ///
    /// Items are grouped by `(sourceID, calendarDay of fetchedAt)`. The slot limit
    /// is enforced per day-group. DigestCards and NudgeCards are only emitted for
    /// the current calendar day so retroactive UI clutter is avoided.
    ///
    /// - Returns: A `RateGateResult` containing digest cards, nudge cards, and hidden item IDs.
    func applyRateGate() -> RateGateResult {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        // Fetch all non-aged-out items regardless of river_visible so previously
        // hidden items can have their visibility restored when limits change.
        let allItems = store.fetchItemsForRateGate()

        // Group: sourceID -> (calendarDayStart -> [item])
        var grouped: [UUID: [Date: [FeedItem]]] = [:]
        for item in allItems {
            let day = calendar.startOfDay(for: item.fetchedAt)
            grouped[item.sourceID, default: [:]][day, default: []].append(item)
        }

        var shouldShow = Set<UUID>()
        var shouldHide = Set<UUID>()
        var digestCards: [DigestCard] = []
        var nudgeCards: [NudgeCard] = []

        for (sourceID, byDay) in grouped {
            // Use the most-recent day's sample item for the velocity tier so
            // re-classified feeds have their new tier reflected immediately.
            let mostRecentDay = byDay.keys.max() ?? todayStart
            let sampleTier = byDay[mostRecentDay]?.first?.velocityTier ?? .article
            let defaultLimit = sampleTier.defaultSlotLimit
            let effectiveLimit = computeEffectiveLimit(
                defaultLimit: defaultLimit,
                sourceID: sourceID
            )

            for (day, dayItems) in byDay {
                let sorted = dayItems.sorted { $0.publishedAt > $1.publishedAt }

                if effectiveLimit < Int.max && sorted.count > effectiveLimit {
                    let visibleItems = Array(sorted.prefix(effectiveLimit))
                    let overflowItems = Array(sorted.dropFirst(effectiveLimit))

                    shouldShow.formUnion(visibleItems.map(\.id))
                    shouldHide.formUnion(overflowItems.map(\.id))

                    // Digest cards are only emitted for today's overflow to
                    // avoid retroactive digest spam for previous days.
                    if day == todayStart {
                        let sourceName = resolveSourceName(sourceID: sourceID)
                        let digest = DigestCard(
                            sourceID: sourceID,
                            sourceName: sourceName,
                            itemCount: overflowItems.count,
                            highlights: Array(overflowItems.prefix(3).map(\.title)),
                            overflowIDs: overflowItems.map(\.id),
                            overflowItems: overflowItems,
                            insertionPosition: overflowItems.first?.publishedAt ?? now
                        )
                        digestCards.append(digest)
                    }
                } else {
                    // All items fit within the limit — ensure they are all visible.
                    shouldShow.formUnion(sorted.map(\.id))
                }
            }

            // Flood detection: rolling 2-hour window on today's items only.
            let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
            let recentItems = (byDay[todayStart] ?? []).filter { $0.publishedAt >= twoHoursAgo }
            if !recentItems.isEmpty,
               detectFlood(sourceID: sourceID, recentCount: recentItems.count) {
                let sourceName = resolveSourceName(sourceID: sourceID)
                nudgeCards.append(NudgeCard(
                    sourceID: sourceID,
                    sourceName: sourceName,
                    itemCount: recentItems.count,
                    message: "\(sourceName) posted \(recentItems.count) articles in the last 2 hours"
                ))
            }
        }

        // Persist both directions so this run is fully self-correcting.
        if !shouldShow.isEmpty { store.setRiverVisible(true,  forItemIDs: Array(shouldShow)) }
        if !shouldHide.isEmpty { store.setRiverVisible(false, forItemIDs: Array(shouldHide)) }

        // #region agent log
        let perSource: [[String: Any]] = grouped.map { sourceID, byDay in
            let totalItems = byDay.values.map(\.count).reduce(0, +)
            let mostRecentDay = byDay.keys.max() ?? todayStart
            let tier = byDay[mostRecentDay]?.first?.velocityTier.rawValue ?? "?"
            let defaultLimit = byDay[mostRecentDay]?.first?.velocityTier.defaultSlotLimit ?? 0
            let hidden = byDay.values.flatMap { $0 }.filter { shouldHide.contains($0.id) }.count
            return [
                "sourceID": sourceID.uuidString.prefix(8),
                "tier": tier,
                "defaultLimit": defaultLimit,
                "totalItemsInGroup": totalItems,
                "hiddenCount": hidden,
                "daysInGroup": byDay.keys.count,
                "mostRecentDayCount": byDay[mostRecentDay]?.count ?? 0
            ]
        }
        DebugLog.log("H3", "RateGateService.swift:130", "rateGate.done", [
            "totalItems": allItems.count,
            "shownCount": shouldShow.count,
            "hiddenCount": shouldHide.count,
            "digestCards": digestCards.count,
            "nudgeCards": nudgeCards.count,
            "perSource": perSource
        ])
        // #endregion

        return RateGateResult(
            digestCards: digestCards,
            nudgeCards: nudgeCards,
            hiddenItemIDs: shouldHide
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
            // Reduce, but keep a minimum of 2 so high-velocity sources (e.g. .breaking
            // with defaultLimit=3) never collapse to a single article from mild negative affinity.
            return max(2, defaultLimit - 2)
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
