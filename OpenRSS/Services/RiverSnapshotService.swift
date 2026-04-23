//
//  RiverSnapshotService.swift
//  OpenRSS
//
//  Phase 2a — Stage 5 of the River Pipeline.
//  Constructs [RiverItem] from scored items + DigestCards + NudgeCards,
//  diffs against the previous snapshot using stable RiverItem.id values,
//  and emits deltas via a PassthroughSubject.
//

import Foundation
import Combine

// MARK: - RiverSnapshotService

final class RiverSnapshotService: @unchecked Sendable {

    // MARK: - Dependencies

    private let store: SQLiteStore

    // MARK: - Previous Snapshot (for diffing)

    private var previousItemIDs: Set<UUID> = []

    init(store: SQLiteStore = .shared) {
        self.store = store
    }

    // MARK: - Public API

    /// Assembles a RiverSnapshot from the current SQLite state and rate gate output.
    ///
    /// Clusters are collapsed into ClusterCard entries; non-clustered items remain
    /// as individual articles. DigestCards and NudgeCards from the rate gate stage
    /// are inserted at their computed positions.
    ///
    /// The service diffs against the previous snapshot's item IDs so downstream
    /// consumers can distinguish new vs. reordered items.
    ///
    /// - Parameter rateGateResult: Output from Stage 3 (may be nil on scoring-only cycles).
    /// - Returns: A `RiverSnapshot` containing the sorted river items.
    func assembleSnapshot(rateGateResult: RateGateResult?) -> RiverSnapshot {
        // Use the full 30-day history so the feed is scrollable beyond the current
        // ~7-day aged-out window. river_visible=1 still respects rate gating.
        // Decay opacity in the UI provides the recency hierarchy — no hard cutoff needed.
        let riverItems = store.fetchRiverItemsAllHistory()

        // Group clustered items by clusterID
        var clusterBuckets: [UUID: [FeedItem]] = [:]
        var standaloneItems: [FeedItem] = []

        for item in riverItems {
            if let clusterID = item.clusterID {
                clusterBuckets[clusterID, default: []].append(item)
            } else {
                standaloneItems.append(item)
            }
        }

        var items: [RiverItem] = standaloneItems.map { .article($0) }

        // Build ClusterCards from grouped items
        for (clusterID, clusterItems) in clusterBuckets {
            guard clusterItems.count >= 2 else {
                // Single-item "clusters" are just articles
                items.append(contentsOf: clusterItems.map { .article($0) })
                continue
            }

            let canonical = clusterItems.first(where: { $0.isCanonical }) ?? clusterItems[0]
            let sourceIDs = Array(Set(clusterItems.map(\.sourceID)))
            let sourceNames = sourceIDs.map(\.uuidString)
            let allIDs = clusterItems.map(\.id)

            let card = ClusterCard(
                id: clusterID,
                canonicalItem: canonical,
                sourceCount: sourceNames.count,
                sourceNames: sourceNames,
                allItemIDs: allIDs,
                allItems: clusterItems
            )
            items.append(.cluster(card))
        }

        // Add DigestCards and NudgeCards from the rate gate stage
        if let rateGateResult {
            for digest in rateGateResult.digestCards {
                items.append(.digest(digest))
            }
            for nudge in rateGateResult.nudgeCards {
                items.append(.nudge(nudge))
            }
        }

        // Sort by positional weight (relevance score) descending
        let sorted = items.sorted { $0.positionalWeight > $1.positionalWeight }

        // Diff against previous snapshot
        let currentIDs = Set(sorted.map(\.id))
        let newIDs = currentIDs.subtracting(previousItemIDs)
        let removedIDs = previousItemIDs.subtracting(currentIDs)
        previousItemIDs = currentIDs

        if !newIDs.isEmpty || !removedIDs.isEmpty {
            let added = newIDs.count
            let removed = removedIDs.count
            print("Snapshot diff: +\(added) -\(removed) items (total: \(sorted.count))")
        }

        return RiverSnapshot(items: sorted)
    }
}
