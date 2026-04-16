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
    let snapshotPublisher = PassthroughSubject<RiverSnapshot, Never>()

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

        // Stage 1 — Ingest
        let (_, _) = await timer.time("Stage1-Ingest") {
            await ingestService.ingest(sources: sources, velocityOverrides: velocityOverrides)
        }

        // Stage 2 — Semantic Clustering
        let (_, _) = timer.time("Stage2-Clustering") {
            clusterService.clusterRecentItems()
        }

        // Stage 3 — Rate Gating
        let (rateGateResult, _) = timer.time("Stage3-RateGate") {
            rateGateService.applyRateGate()
        }
        lastRateGateResult = rateGateResult

        // Stage 4 — Decay Scoring
        let (agedOut, scoringMs) = timer.time("Stage4-DecayScoring") {
            decayService.scoreAllItems()
        }
        _ = agedOut
        _ = scoringMs

        // Stage 5 — Snapshot Assembly (via RiverSnapshotService)
        let (snapshot, snapshotMs) = timer.time("Stage5-Snapshot") {
            snapshotService.assembleSnapshot(rateGateResult: lastRateGateResult)
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
            snapshotService.assembleSnapshot(rateGateResult: lastRateGateResult)
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

    // MARK: - Maintenance

    /// Purges old aged-out items from the database.
    func purgeOldItems(olderThan days: Int = 30) {
        store.purgeAgedItems(olderThan: days)
    }
}
