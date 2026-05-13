//
//  PerformanceAndClusteringTests.swift
//  OpenRSSTests
//
//  Tests validating the three optimizations on the V1-DEV branch:
//    1. Concurrent feed ingestion (FeedIngestService)
//    2. Cluster-aware rate gating (RateGateService)
//    3. Batched SQL operations (SQLiteStore, DecayScoringService)
//
//  Run with Cmd+U in Xcode or: xcodebuild test -scheme OpenRSS
//

import Testing
import Foundation
@testable import OpenRSS


// =============================================================================
// MARK: - 1. CLUSTER-AWARE RATE GATING TESTS
// =============================================================================
//
// What this tests:
//   The rate gate must treat clustered items as a single unit when enforcing
//   per-source daily slot limits. Before this fix, canonical cluster items
//   could be hidden by rate gating, which caused the entire cluster to
//   disappear from the river UI.
//
// Why it matters:
//   If canonical items are hidden, RiverSnapshotService can't build
//   ClusterCards, and users see empty feeds despite having clustered content.
//

struct ClusterAwareRateGateTests {

    /// Creates a test FeedItem fetched today with the given parameters.
    private func makeTodayItem(
        sourceID: UUID,
        title: String = "Test",
        velocityTier: VelocityTier = .news,
        hoursAgo: Double = 0.5,
        clusterID: UUID? = nil,
        isCanonical: Bool = false
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            clusterID: clusterID,
            isCanonical: isCanonical,
            velocityTier: velocityTier,
            riverVisible: true
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Canonical cluster items are never hidden by rate gating
    //
    // Scenario: 10 items from one .news source (slot limit = 5). Items 0-2
    //   form a cluster (item 0 is canonical). Items 3-9 are standalone.
    //
    // Expected: The canonical item (item 0) must remain visible. The cluster
    //   counts as 1 slot, so we have 1 cluster + 7 standalone = 8 units.
    //   With limit 5, only 3 standalone items overflow — never the canonical.
    // -------------------------------------------------------------------------
    @Test func canonicalClusterItemsAreNeverHidden() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()
        let clusterID = UUID()

        var items: [FeedItem] = []
        for i in 0..<10 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "Cluster Test \(i) \(UUID())",
                velocityTier: .news,
                hoursAgo: 0.05 * Double(i)
            )
            // Items 0, 1, 2 form a cluster
            if i < 3 {
                item.clusterID = clusterID
                item.isCanonical = (i == 0)
            }
            items.append(item)
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()

        // The canonical item must NOT be hidden
        #expect(!result.hiddenItemIDs.contains(items[0].id),
                "Canonical cluster item must never be hidden by rate gating")
    }

    // -------------------------------------------------------------------------
    // TEST: Non-canonical cluster members follow their canonical item
    //
    // Scenario: Same as above. If the canonical is visible, all non-canonical
    //   members of that cluster should also be visible (they don't consume slots).
    // -------------------------------------------------------------------------
    @Test func nonCanonicalMembersFollowCanonical() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()
        let clusterID = UUID()

        var items: [FeedItem] = []
        for i in 0..<10 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "Follow Test \(i) \(UUID())",
                velocityTier: .news,
                hoursAgo: 0.05 * Double(i)
            )
            if i < 3 {
                item.clusterID = clusterID
                item.isCanonical = (i == 0)
            }
            items.append(item)
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()

        // All cluster members should follow the canonical's visibility
        #expect(!result.hiddenItemIDs.contains(items[1].id),
                "Non-canonical cluster member should be visible when canonical is visible")
        #expect(!result.hiddenItemIDs.contains(items[2].id),
                "Non-canonical cluster member should be visible when canonical is visible")
    }

    // -------------------------------------------------------------------------
    // TEST: Clusters count as one slot, not N slots
    //
    // Scenario: .breaking source (slot limit = 3). 3 items clustered (= 1 slot)
    //   + 3 standalone items (= 3 slots). Total units = 4. Limit = 3.
    //   So 1 standalone item overflows, but the cluster stays intact.
    //
    // Expected: Exactly 1 item is hidden (a standalone), not any cluster member.
    // -------------------------------------------------------------------------
    @Test func clusterCountsAsOneSlot() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()
        let clusterID = UUID()

        // 3 clustered items (1 slot)
        var clustered: [FeedItem] = []
        for i in 0..<3 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "Clustered \(i) \(UUID())",
                velocityTier: .breaking,
                hoursAgo: 0.01 * Double(i)
            )
            item.clusterID = clusterID
            item.isCanonical = (i == 0)
            clustered.append(item)
        }

        // 3 standalone items (3 slots)
        let standalone = (0..<3).map { i in
            makeTodayItem(
                sourceID: sourceID,
                title: "Standalone \(i) \(UUID())",
                velocityTier: .breaking,
                hoursAgo: 0.05 + 0.01 * Double(i)
            )
        }

        let allItems = clustered + standalone
        store.upsertFeedItems(allItems)

        let result = service.applyRateGate()

        // No cluster members should be hidden
        let hiddenCluster = clustered.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenCluster.isEmpty,
                "No cluster members should be hidden — the cluster uses only 1 slot")

        // 1 cluster slot + 3 standalone = 4 units, limit = 3, so 1 standalone hidden
        let hiddenStandalone = standalone.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenStandalone.count == 1,
                "Expected 1 standalone item hidden (4 units - 3 limit = 1 overflow), got \(hiddenStandalone.count)")
    }

    // -------------------------------------------------------------------------
    // TEST: Multiple clusters from same source each count as one slot
    //
    // Scenario: .breaking source (limit 3). 2 clusters of 2 items each (= 2 slots)
    //   + 2 standalone (= 2 slots). Total units = 4. Limit = 3. 1 overflows.
    //
    // Expected: Both clusters stay intact. 1 standalone is hidden.
    // -------------------------------------------------------------------------
    @Test func multipleClustersEachCountAsOneSlot() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()
        let cluster1ID = UUID()
        let cluster2ID = UUID()

        var cluster1Items: [FeedItem] = []
        for i in 0..<2 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "C1 Item \(i) \(UUID())",
                velocityTier: .breaking,
                hoursAgo: 0.01 * Double(i)
            )
            item.clusterID = cluster1ID
            item.isCanonical = (i == 0)
            cluster1Items.append(item)
        }

        var cluster2Items: [FeedItem] = []
        for i in 0..<2 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "C2 Item \(i) \(UUID())",
                velocityTier: .breaking,
                hoursAgo: 0.03 + 0.01 * Double(i)
            )
            item.clusterID = cluster2ID
            item.isCanonical = (i == 0)
            cluster2Items.append(item)
        }

        let standalone = (0..<2).map { i in
            makeTodayItem(
                sourceID: sourceID,
                title: "Standalone Multi \(i) \(UUID())",
                velocityTier: .breaking,
                hoursAgo: 0.06 + 0.01 * Double(i)
            )
        }

        store.upsertFeedItems(cluster1Items + cluster2Items + standalone)

        let result = service.applyRateGate()

        // Both clusters should be fully visible
        let allClusterItems = cluster1Items + cluster2Items
        let hiddenCluster = allClusterItems.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenCluster.isEmpty,
                "No cluster members from either cluster should be hidden")

        // 2 cluster slots + 2 standalone = 4 units, limit 3 -> 1 overflow
        let hiddenStandalone = standalone.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenStandalone.count == 1,
                "Expected 1 standalone overflow, got \(hiddenStandalone.count)")
    }

    // -------------------------------------------------------------------------
    // TEST: End-to-end: clustered items survive into the final snapshot
    //
    // Scenario: Insert clustered items, run rate gating, then assemble a
    //   snapshot. The cluster should appear as a .cluster RiverItem.
    //
    // Expected: The snapshot contains a ClusterCard with all cluster members.
    // -------------------------------------------------------------------------
    @Test func clusteredItemsSurviveIntoSnapshot() {
        let store = SQLiteStore.shared
        let rateGateService = RateGateService(store: store)
        let snapshotService = RiverSnapshotService(store: store)
        let sourceID = UUID()
        let clusterID = UUID()

        // 3 clustered items
        var items: [FeedItem] = []
        for i in 0..<3 {
            var item = makeTodayItem(
                sourceID: sourceID,
                title: "E2E Cluster \(i) \(UUID())",
                velocityTier: .news,
                hoursAgo: 0.01 * Double(i)
            )
            item.clusterID = clusterID
            item.isCanonical = (i == 0)
            items.append(item)
        }
        store.upsertFeedItems(items)
        store.updateScores(items.map { (id: $0.id, relevanceScore: 0.9, agedOut: false) })

        // Run rate gating
        let rateResult = rateGateService.applyRateGate()

        // Assemble snapshot
        let snapshot = snapshotService.assembleSnapshot(rateGateResult: rateResult)

        // Find our cluster in the snapshot
        let clusterCards = snapshot.items.compactMap { riverItem -> ClusterCard? in
            if case .cluster(let card) = riverItem, card.id == clusterID { return card }
            return nil
        }

        #expect(clusterCards.count == 1,
                "Clustered items should appear as a ClusterCard in the snapshot")

        if let card = clusterCards.first {
            #expect(card.allItemIDs.count == 3,
                    "ClusterCard should contain all 3 items, got \(card.allItemIDs.count)")
        }
    }
}


// =============================================================================
// MARK: - 2. BATCHED SQL OPERATIONS TESTS
// =============================================================================
//
// What this tests:
//   The batched versions of existingItemIDs (IN clause) and setRiverVisible
//   (IN clause) produce the same results as the old per-item approach, but
//   faster. Also tests that DecayScoringService correctly pre-fetches
//   affinities instead of querying per-item.
//
// Why it matters:
//   Incorrect batching could miss items (false negatives in dedup) or fail
//   to update visibility, breaking the river feed.
//

struct BatchedSQLTests {

    // -------------------------------------------------------------------------
    // TEST: existingItemIDs correctly identifies existing items in batch
    //
    // Scenario: Insert 100 items. Query with 100 existing + 50 non-existing IDs.
    // Expected: Returns exactly the 100 existing IDs.
    // -------------------------------------------------------------------------
    @Test func existingItemIDsBatchAccuracy() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<100).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Batch Dedup \(i) \(UUID())",
                link: URL(string: "https://batch.com/\(UUID().uuidString)")!,
                publishedAt: Date()
            )
        }
        store.upsertFeedItems(items)

        let existingSet = Set(items.map(\.id))
        let fakeIDs = Set((0..<50).map { _ in UUID() })
        let candidates = existingSet.union(fakeIDs)

        let result = store.existingItemIDs(from: candidates)

        #expect(result == existingSet,
                "Should find exactly the 100 existing IDs, found \(result.count)")
        #expect(result.intersection(fakeIDs).isEmpty,
                "Should not return any fake IDs")
    }

    // -------------------------------------------------------------------------
    // TEST: existingItemIDs handles large batches (over chunk size of 500)
    //
    // Scenario: Insert 600 items. Query all 600.
    // Expected: All 600 found. This exercises the chunking logic.
    // -------------------------------------------------------------------------
    @Test func existingItemIDsLargeBatch() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<600).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Large Batch \(i) \(UUID())",
                link: URL(string: "https://large.com/\(UUID().uuidString)")!,
                publishedAt: Date()
            )
        }
        store.upsertFeedItems(items)

        let candidates = Set(items.map(\.id))
        let result = store.existingItemIDs(from: candidates)

        #expect(result.count == 600,
                "All 600 items should be found, got \(result.count)")
    }

    // -------------------------------------------------------------------------
    // TEST: existingItemIDs returns empty set for empty input
    //
    // Expected: Empty input -> empty output, no crash.
    // -------------------------------------------------------------------------
    @Test func existingItemIDsEmptyInput() {
        let store = SQLiteStore.shared
        let result = store.existingItemIDs(from: [])
        #expect(result.isEmpty, "Empty candidates should return empty result")
    }

    // -------------------------------------------------------------------------
    // TEST: setRiverVisible correctly batch-updates visibility
    //
    // Scenario: Insert 50 items (all visible), hide 20 of them in batch.
    // Expected: Those 20 no longer appear in fetchRiverItems().
    // -------------------------------------------------------------------------
    @Test func setRiverVisibleBatchUpdate() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<50).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Visibility Batch \(i) \(UUID())",
                link: URL(string: "https://vis.com/\(UUID().uuidString)")!,
                publishedAt: Date(),
                relevanceScore: 0.9,
                riverVisible: true
            )
        }
        store.upsertFeedItems(items)
        store.updateScores(items.map { (id: $0.id, relevanceScore: 0.9, agedOut: false) })

        // Hide the first 20
        let toHide = Array(items.prefix(20).map(\.id))
        store.setRiverVisible(false, forItemIDs: toHide)

        // Verify: the hidden items should not appear in river query
        let riverItems = store.fetchRiverItems()
        let riverIDs = Set(riverItems.map(\.id))

        for hiddenID in toHide {
            #expect(!riverIDs.contains(hiddenID),
                    "Hidden item should not appear in river results")
        }

        // The other 30 should still be visible
        let visibleIDs = items.suffix(30).map(\.id)
        for visibleID in visibleIDs {
            #expect(riverIDs.contains(visibleID),
                    "Non-hidden item should still appear in river results")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: setRiverVisible handles large batches (over chunk size)
    //
    // Scenario: Hide 600 items in one call.
    // Expected: All 600 correctly hidden.
    // -------------------------------------------------------------------------
    @Test func setRiverVisibleLargeBatch() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<600).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Large Vis \(i) \(UUID())",
                link: URL(string: "https://largevis.com/\(UUID().uuidString)")!,
                publishedAt: Date(),
                relevanceScore: 0.9,
                riverVisible: true
            )
        }
        store.upsertFeedItems(items)
        store.updateScores(items.map { (id: $0.id, relevanceScore: 0.9, agedOut: false) })

        store.setRiverVisible(false, forItemIDs: items.map(\.id))

        let riverItems = store.fetchRiverItems()
        let riverIDs = Set(riverItems.map(\.id))
        let stillVisible = items.filter { riverIDs.contains($0.id) }

        #expect(stillVisible.isEmpty,
                "All 600 items should be hidden, but \(stillVisible.count) remain visible")
    }
}


// =============================================================================
// MARK: - 3. AFFINITY CACHE TESTS
// =============================================================================
//
// What this tests:
//   DecayScoringService now pre-fetches all affinity records once instead
//   of querying per-item. These tests verify the scoring results are
//   identical to the old approach.
//
// Why it matters:
//   If the cache gives wrong boost values, the entire ranking order changes.
//

struct AffinityCacheTests {

    // -------------------------------------------------------------------------
    // TEST: Items from sources with affinity get the correct boost
    //
    // Scenario: 2 sources, one with affinity 0.4, one with no affinity.
    //   Insert one item from each. Run scoreAllItems().
    //
    // Expected: The boosted item has higher relevance than raw decay.
    //   The non-boosted item matches raw decay exactly.
    // -------------------------------------------------------------------------
    @Test func affinityCacheProducesCorrectBoosts() {
        let store = SQLiteStore.shared
        let boostedSourceID = UUID()
        let plainSourceID = UUID()
        let hoursAgo = 8.0

        // Set up affinity for one source only
        let affinity = SourceAffinityRecord(
            sourceID: boostedSourceID,
            affinityScore: 0.4,
            eventCount: 15,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(affinity)

        let boostedItem = FeedItem(
            sourceID: boostedSourceID,
            title: "Affinity Cache Boosted \(UUID())",
            link: URL(string: "https://cache.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            velocityTier: .news,
            relevanceScore: 1.0
        )
        let plainItem = FeedItem(
            sourceID: plainSourceID,
            title: "Affinity Cache Plain \(UUID())",
            link: URL(string: "https://cache.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            velocityTier: .news,
            relevanceScore: 1.0
        )

        store.upsertFeedItems([boostedItem, plainItem])

        let service = DecayScoringService()
        service.scoreAllItems()

        let rawRelevance = DecayScoringService.relevance(hoursSincePublished: hoursAgo, tier: .news)

        // Check boosted item
        let fetchedBoosted = store.fetchItems(forSource: boostedSourceID)
        if let found = fetchedBoosted.first(where: { $0.id == boostedItem.id }) {
            #expect(found.relevanceScore > rawRelevance,
                    "Boosted item (\(found.relevanceScore)) should exceed raw decay (\(rawRelevance))")
            // Expected: rawRelevance * (1 + 0.4) = rawRelevance * 1.4
            let expected = rawRelevance * 1.4
            #expect(abs(found.relevanceScore - expected) < 0.01,
                    "Expected ~\(expected), got \(found.relevanceScore)")
        } else {
            Issue.record("Boosted item not found")
        }

        // Check plain item (no affinity)
        let fetchedPlain = store.fetchItems(forSource: plainSourceID)
        if let found = fetchedPlain.first(where: { $0.id == plainItem.id }) {
            #expect(abs(found.relevanceScore - rawRelevance) < 0.01,
                    "Plain item (\(found.relevanceScore)) should equal raw decay (\(rawRelevance))")
        } else {
            Issue.record("Plain item not found")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Multiple items from the same source all get the same boost
    //
    // Scenario: 1 source with affinity 0.3, insert 5 items at the same age.
    //
    // Expected: All 5 items have the same relevance score (same source, same
    //   age, same boost).
    // -------------------------------------------------------------------------
    @Test func sameSourceItemsGetSameBoost() {
        let store = SQLiteStore.shared
        let sourceID = UUID()
        let hoursAgo = 12.0

        let affinity = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: 0.3,
            eventCount: 10,
            velocityTier: .article,
            slotLimit: 15
        )
        store.upsertAffinity(affinity)

        let items = (0..<5).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Same Source \(i) \(UUID())",
                link: URL(string: "https://same.com/\(UUID().uuidString)")!,
                publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
                velocityTier: .article,
                relevanceScore: 1.0
            )
        }
        store.upsertFeedItems(items)

        let service = DecayScoringService()
        service.scoreAllItems()

        let fetched = store.fetchItems(forSource: sourceID)
        let scores = items.compactMap { item in
            fetched.first(where: { $0.id == item.id })?.relevanceScore
        }

        guard scores.count == 5 else {
            Issue.record("Expected 5 scored items, found \(scores.count)")
            return
        }

        // All scores should be identical (same source, same age, same boost)
        let first = scores[0]
        for (i, score) in scores.enumerated() {
            #expect(abs(score - first) < 0.001,
                    "Item \(i) score \(score) should equal item 0 score \(first)")
        }
    }
}


// =============================================================================
// MARK: - 4. SESSION AFFINITY SNAPSHOT TESTS
// =============================================================================
//
// What this tests:
//   Rate gating uses a frozen affinity snapshot so that reading articles
//   mid-session doesn't shift slot limits and cause DigestCards to vanish.
//
// Why it matters:
//   Without this, a user reads one article → affinity bumps → slot limit
//   increases → the DigestCard disappears on next refresh. The feed layout
//   should stay stable within a single session.
//

struct SessionAffinitySnapshotTests {

    private func makeTodayItem(
        sourceID: UUID,
        title: String = "Test",
        velocityTier: VelocityTier = .news,
        hoursAgo: Double = 0.5
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            velocityTier: velocityTier,
            riverVisible: true
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Affinity changes after snapshot don't affect rate gating
    //
    // Scenario:
    //   1. Source has affinity 0.0 (no boost). Slot limit = 5 for .news.
    //   2. Insert 8 items → 3 overflow → DigestCard created.
    //   3. Freeze snapshot with affinity 0.0.
    //   4. Update affinity to 0.9 in SQLite (simulating article reads).
    //   5. Re-run rate gating with the frozen snapshot.
    //
    // Expected: The digest still has 3 overflow items because rate gating
    //   used the frozen 0.0 score, not the live 0.9 score. If it used the
    //   live score, the boosted limit (7) would absorb the overflow and the
    //   digest would vanish.
    // -------------------------------------------------------------------------
    @Test func affinityChangesAfterSnapshotDontAffectRateGating() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        // Start with neutral affinity
        let initialAffinity = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: 0.0,
            eventCount: 0,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(initialAffinity)

        // Insert 8 items (slot limit 5 → 3 overflow)
        let items = (0..<8).map { i in
            makeTodayItem(
                sourceID: sourceID,
                title: "Snapshot Freeze \(i) \(UUID())",
                velocityTier: .news,
                hoursAgo: 0.05 * Double(i)
            )
        }
        store.upsertFeedItems(items)

        // Freeze the snapshot NOW (affinity = 0.0)
        let snapshot: [UUID: SourceAffinityRecord] = [sourceID: initialAffinity]

        // Simulate user reading articles — affinity jumps to 0.9 in SQLite
        var boostedAffinity = initialAffinity
        boostedAffinity.affinityScore = 0.9
        boostedAffinity.eventCount = 20
        store.upsertAffinity(boostedAffinity)

        // Run rate gating WITH the frozen snapshot
        let result = service.applyRateGate(affinitySnapshot: snapshot)

        // Should still have 3 hidden items (limit 5, not boosted to 7)
        let hiddenFromSource = items.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenFromSource.count == 3,
                "Frozen snapshot (affinity 0.0, limit 5) should hide 3 of 8 items, got \(hiddenFromSource.count)")

        // DigestCard should still exist
        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.count == 1,
                "DigestCard should still exist because snapshot used pre-boost affinity")
    }
}


// =============================================================================
// MARK: - 5. BATCHED SQL PERFORMANCE TESTS
// =============================================================================
//
// What this tests:
//   Wall-clock performance of the batched operations to verify they are
//   faster than the previous per-item approach.
//
// Why it matters:
//   The whole point of batching is speed. If there's no measurable
//   improvement, the refactor added complexity for nothing.
//

struct BatchedSQLPerformanceTests {

    // -------------------------------------------------------------------------
    // TEST: Batched existingItemIDs is fast for 500 candidates
    //
    // Scenario: Insert 500 items, query all 500 + 250 fake IDs.
    // Expected: Completes in < 100ms.
    // -------------------------------------------------------------------------
    @Test func existingItemIDsPerformance() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<500).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Perf Dedup \(i)",
                link: URL(string: "https://perfdedup.com/\(UUID().uuidString)")!,
                publishedAt: Date()
            )
        }
        store.upsertFeedItems(items)

        let existingIDs = Set(items.map(\.id))
        let fakeIDs = Set((0..<250).map { _ in UUID() })
        let candidates = existingIDs.union(fakeIDs)

        let start = CFAbsoluteTimeGetCurrent()
        let result = store.existingItemIDs(from: candidates)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(result.count == 500, "Should find all 500 items")
        #expect(elapsed < 100,
                "Batched dedup for 750 candidates should complete in <100ms, took \(String(format: "%.1f", elapsed))ms")
    }

    // -------------------------------------------------------------------------
    // TEST: Batched setRiverVisible is fast for 500 items
    //
    // Scenario: Hide 500 items in one call.
    // Expected: Completes in < 100ms.
    // -------------------------------------------------------------------------
    @Test func setRiverVisiblePerformance() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<500).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Perf Vis \(i)",
                link: URL(string: "https://perfvis.com/\(UUID().uuidString)")!,
                publishedAt: Date(),
                riverVisible: true
            )
        }
        store.upsertFeedItems(items)

        let ids = items.map(\.id)

        let start = CFAbsoluteTimeGetCurrent()
        store.setRiverVisible(false, forItemIDs: ids)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 100,
                "Batched visibility update for 500 items should complete in <100ms, took \(String(format: "%.1f", elapsed))ms")
    }

    // -------------------------------------------------------------------------
    // TEST: Decay scoring with pre-fetched affinities is fast
    //
    // Scenario: Insert 200 items across 20 sources (each with affinity records).
    //   Run scoreAllItems().
    //
    // Expected: Completes in < 500ms (previously O(n) DB calls, now O(1)).
    // -------------------------------------------------------------------------
    @Test func decayScoringWithAffinityCachePerformance() {
        let store = SQLiteStore.shared

        // Create 20 sources with affinities
        let sourceIDs = (0..<20).map { _ in UUID() }
        for sourceID in sourceIDs {
            let affinity = SourceAffinityRecord(
                sourceID: sourceID,
                affinityScore: Double.random(in: 0...0.5),
                eventCount: 10,
                velocityTier: .news,
                slotLimit: 5
            )
            store.upsertAffinity(affinity)
        }

        // 10 items per source = 200 items
        var allItems: [FeedItem] = []
        for sourceID in sourceIDs {
            for i in 0..<10 {
                let item = FeedItem(
                    sourceID: sourceID,
                    title: "Perf Score \(UUID())",
                    link: URL(string: "https://perfscore.com/\(UUID().uuidString)")!,
                    publishedAt: Date().addingTimeInterval(-Double(i) * 3600),
                    velocityTier: .news,
                    relevanceScore: 1.0
                )
                allItems.append(item)
            }
        }
        store.upsertFeedItems(allItems)

        let service = DecayScoringService()

        let start = CFAbsoluteTimeGetCurrent()
        service.scoreAllItems()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 500,
                "Scoring 200 items with cached affinities should complete in <500ms, took \(String(format: "%.1f", elapsed))ms")
    }
}
