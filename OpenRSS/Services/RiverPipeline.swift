//
//  RiverPipeline.swift
//  OpenRSS
//
//  Phase 2a — Orchestrates the River pipeline stages.
//  Runs on a background actor. Only the final snapshot emission
//  crosses to the main actor via Combine.
//
//  Current stages:
//    1. FeedIngestService       — fetch + parse + dedup
//    2. SemanticClusterService  — three-pass story clustering
//    3. RateGateService         — daily slot limits + digest bundling + flood detection
//    4. DecayScoringService     — exponential decay scoring
//    5. Snapshot assembly       — build [RiverItem] and emit
//

import Foundation
import Combine

// MARK: - RiverPipeline

final class RiverPipeline: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = RiverPipeline()

    // MARK: - Publishers

    /// View layer subscribes to this for snapshot updates.
    /// CurrentValueSubject ensures late subscribers (e.g. SearchView) immediately
    /// receive the last emitted snapshot instead of waiting for the next pipeline cycle.
    let snapshotPublisher = CurrentValueSubject<RiverSnapshot, Never>(RiverSnapshot(items: [], pipelineDurationMs: 0))

    // MARK: - Dependencies

    private let ingestService = FeedIngestService()
    private let clusterService = SemanticClusterService()
    private let rateGateService = RateGateService()
    private let decayService = DecayScoringService()
    private let snapshotService = RiverSnapshotService()
    private let store = SQLiteStore.shared
    private let timer = PipelineTimer()

    // MARK: - State

    /// Serial queue for pipeline execution — prevents overlapping cycles.
    private let pipelineQueue = DispatchQueue(label: "com.openrss.pipeline", qos: .userInitiated)
    private var isRunning = false

    /// Cached rate gate result from the last pipeline run (used by snapshot assembly).
    private var lastRateGateResult: RateGateResult?

    /// Cached `sourceID → preferUniqueStories` map from the last pipeline run.
    /// Captured on the main actor at the start of a cycle so subsequent
    /// `runScoringCycle()` calls can re-sort using the same preferences without
    /// hopping back to the main actor.
    private var lastPreferUniqueStories: [UUID: Bool] = [:]

    /// Affinity scores frozen at the first pipeline cycle of this session.
    /// Used by rate gating so that reading articles mid-session doesn't change
    /// slot limits and cause DigestCards to flicker or disappear.
    /// Reset on next app launch (new RiverPipeline instance).
    private var sessionAffinitySnapshot: [UUID: SourceAffinityRecord]?

    private init() {}

    // MARK: - Public API

    /// Runs a full pipeline cycle: ingest -> score -> snapshot.
    /// Safe to call from any thread; execution is serialized.
    func runCycle(sources: [Source], velocityOverrides: [UUID: VelocityTier] = [:]) async {
        // Prevent overlapping runs
        let shouldRun: Bool = pipelineQueue.sync {
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        guard shouldRun else { return }

        defer {
            pipelineQueue.sync { isRunning = false }
        }

        let totalStart = CFAbsoluteTimeGetCurrent()

        // Capture per-source "prefer unique stories" flags for the snapshot stage.
        // Using the `sources` snapshot the caller already passed in keeps this
        // off the main actor and avoids re-reading SwiftDataService here.
        lastPreferUniqueStories = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.id, $0.preferUniqueStories) }
        )

        // Stage 1 — Ingest
        let (ingestResult, _) = await timer.time("Stage1-Ingest") {
            await ingestService.ingest(sources: sources, velocityOverrides: velocityOverrides)
        }

        // #region agent log
        let ingestBySource: [[String: Any]] = Dictionary(grouping: ingestResult, by: \.sourceID)
            .map { sid, items in
                let name = sources.first { $0.id == sid }?.name ?? sid.uuidString
                return [
                    "source": name,
                    "newCount": items.count,
                    "tier": items.first?.velocityTier.rawValue ?? "n/a"
                ]
            }
        DebugLog.log("H4", "RiverPipeline.swift:91", "pipeline.stage1.ingest", [
            "newItemsTotal": ingestResult.count,
            "sourcesAttempted": sources.filter(\.isEnabled).count,
            "perSource": ingestBySource
        ])
        // #endregion

        // Stage 2 — Semantic Clustering
        let (_, _) = timer.time("Stage2-Clustering") {
            clusterService.clusterRecentItems()
        }

        // Freeze affinity scores on the first pipeline cycle of this session.
        // Subsequent cycles reuse the same snapshot so that reading articles
        // mid-session doesn't shift slot limits and cause DigestCards to vanish.
        if sessionAffinitySnapshot == nil {
            let allAffinities = store.fetchAllAffinities()
            sessionAffinitySnapshot = Dictionary(
                uniqueKeysWithValues: allAffinities.map { ($0.sourceID, $0) }
            )
        }

        // Stage 3 — Rate Gating
        let (rateGateResult, _) = timer.time("Stage3-RateGate") {
            rateGateService.applyRateGate(affinitySnapshot: sessionAffinitySnapshot)
        }
        lastRateGateResult = rateGateResult

        // Stage 3b — Repair cluster visibility.
        // Rate gating may have hidden non-canonical cluster members because they
        // belong to a different source with its own slot limit. Ensure all members
        // of a cluster share the canonical item's river_visible status so the
        // snapshot assembler can build a complete ClusterCard.
        timer.time("Stage3b-ClusterVisibility") {
            repairClusterVisibility()
        }

        // Stage 4 — Decay Scoring
        let (agedOut, scoringMs) = timer.time("Stage4-DecayScoring") {
            decayService.scoreAllItems()
        }
        _ = agedOut
        _ = scoringMs

        // Stage 5 — Snapshot Assembly (via RiverSnapshotService)
        let (snapshot, snapshotMs) = timer.time("Stage5-Snapshot") {
            snapshotService.assembleSnapshot(
                rateGateResult: lastRateGateResult,
                preferUniqueStories: lastPreferUniqueStories
            )
        }
        _ = snapshotMs

        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        timer.logTotal(totalMs, itemCount: snapshot.items.count)

        // Emit to subscribers (main thread)
        let finalSnapshot = RiverSnapshot(
            items: snapshot.items,
            generatedAt: Date(),
            pipelineDurationMs: totalMs
        )
        snapshotPublisher.send(finalSnapshot)
    }

    /// Runs only the scoring + snapshot stages (no network fetch).
    /// Useful for re-scoring after time passes without fetching new items.
    func runScoringCycle() {
        let totalStart = CFAbsoluteTimeGetCurrent()

        let (_, scoringMs) = timer.time("Rescore-DecayScoring") {
            decayService.scoreAllItems()
        }
        _ = scoringMs

        let (snapshot, _) = timer.time("Rescore-Snapshot") {
            snapshotService.assembleSnapshot(
                rateGateResult: lastRateGateResult,
                preferUniqueStories: lastPreferUniqueStories
            )
        }

        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        timer.logTotal(totalMs, itemCount: snapshot.items.count)

        let finalSnapshot = RiverSnapshot(
            items: snapshot.items,
            generatedAt: Date(),
            pipelineDurationMs: totalMs
        )
        snapshotPublisher.send(finalSnapshot)
    }

    // MARK: - Cluster Visibility Repair

    /// Ensures non-canonical cluster members share their canonical item's visibility.
    ///
    /// Rate gating sets `river_visible` per-source, but clusters span multiple sources.
    /// A non-canonical item from source B may be hidden by source B's slot limit even
    /// though the canonical item from source A is visible. This breaks the cluster in
    /// the snapshot assembler (needs count >= 2 visible items to build a ClusterCard).
    ///
    /// This method finds all clusters where the canonical is visible and ensures every
    /// non-canonical member is also visible.
    private func repairClusterVisibility() {
        let cutoff = Date().addingTimeInterval(-12 * 3600) // match cluster window
        // Must fetch ALL clustered items including hidden ones — fetchRecentItems
        // filters by river_visible=1 which means we'd never see the hidden
        // non-canonical members we need to un-hide.
        let clusteredItems = store.fetchClusteredItems(since: cutoff)

        // Group by clusterID
        var clusterBuckets: [UUID: [FeedItem]] = [:]
        for item in clusteredItems {
            clusterBuckets[item.clusterID!, default: []].append(item)
        }

        var toShow: [UUID] = []
        for (_, members) in clusterBuckets {
            guard members.count >= 2 else { continue }
            let canonical = members.first(where: { $0.isCanonical })
            // If canonical is visible, make all non-canonical members visible too
            if canonical?.riverVisible == true {
                for member in members where !member.isCanonical && !member.riverVisible {
                    toShow.append(member.id)
                }
            }
        }

        if !toShow.isEmpty {
            store.setRiverVisible(true, forItemIDs: toShow)
        }
    }

    // MARK: - Maintenance

    /// Purges old aged-out items from the database.
    func purgeOldItems(olderThan days: Int = 30) {
        store.purgeAgedItems(olderThan: days)
    }
}
