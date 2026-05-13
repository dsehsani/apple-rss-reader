//
//  SemanticClusterService.swift
//  OpenRSS
//
//  Phase 2b — Stage 2 of the River Pipeline.
//  Two-phase system: dedup then cluster.
//    Phase A: Deduplicate exact same titles across sources (wire copy)
//    Phase B: Three-pass clustering for same-story, different-coverage articles:
//      Pass 1: SimHash + temporal proximity (cheap candidate generation)
//      Pass 2: Sentence embedding cosine similarity (semantic confirmation)
//      Pass 3: NER entity overlap (final confirmation, skipped when embeddings are strong)
//
//  Only clusters cross-source items within a 12-hour window.
//

import Foundation
import NaturalLanguage
import os.log

// MARK: - SemanticClusterService

final class SemanticClusterService: Sendable {

    // MARK: - Dependencies

    private let store = SQLiteStore.shared
    private let embeddingProvider: (any EmbeddingProvider)?
    private let logger = Logger(subsystem: "com.openrss", category: "Clustering")

    // MARK: - Embedding provider key for cache invalidation
    private static let embeddingProviderKey = "SemanticCluster.embeddingProvider"

    // MARK: - Configuration

    /// Maximum age (in seconds) for items to be considered for clustering.
    private static let clusterWindowSeconds: TimeInterval = 12 * 3600

    /// SimHash hamming distance threshold for Pass 1 candidates.
    /// Relaxed from 3 to 10 so differently-worded articles about the same
    /// story are caught as candidates. Pass 2 embeddings do the real filtering.
    private static let simhashThreshold = 10

    /// Cosine similarity threshold for Pass 2 embedding comparison.
    /// With CoreML MiniLM: same-story pairs score 0.80-0.95, same-beat
    /// pairs score 0.40-0.60, so 0.72 catches real clusters without
    /// false positives. Falls back to NLEmbedding (weaker separation)
    /// where the threshold still works but clustering fires less often.
    private static let embeddingSimilarityThreshold: Float = 0.72

    /// Minimum shared NER entities for Pass 3 confirmation.
    /// Requires 2 shared entities to confirm clustering. One shared entity
    /// (e.g. "Apple") is too common and causes false positives across
    /// same-beat coverage.
    private static let minSharedEntities = 2

    /// Embedding similarity above this skips the NER gate entirely.
    /// With CoreML MiniLM, same-story pairs score 0.72-0.95 and same-beat
    /// pairs top out at ~0.58, so 0.75 safely bypasses NER for real
    /// clusters without risking false positives.
    private static let highConfidenceEmbeddingThreshold: Float = 0.75

    /// SimHash distance at or below which two titles are considered exact
    /// duplicates (same wire copy). These get deduped, not clustered.
    private static let exactDuplicateSimhashThreshold = 2

    // MARK: - Init

    init() {
        self.embeddingProvider = EmbeddingProviderFactory.makeProvider()

        // When the embedding provider changes (e.g. NLEmbedding → CoreML),
        // cached vectors are from a different embedding space and must be
        // cleared. Track which provider produced the current cache.
        let currentProvider = embeddingProvider is CoreMLEmbeddingProvider ? "coreml" : "nlembedding"
        let previousProvider = UserDefaults.standard.string(forKey: Self.embeddingProviderKey)
        if previousProvider != currentProvider {
            store.clearAllEmbeddings()
            UserDefaults.standard.set(currentProvider, forKey: Self.embeddingProviderKey)
        }

        if let provider = embeddingProvider {
            logger.info("Embedding provider: \(String(describing: type(of: provider))) (\(provider.dimensions)-dim)")
        } else {
            logger.warning("No embedding provider available — clustering disabled")
        }
    }

    // MARK: - Public API

    /// Runs the dedup + clustering pipeline on recent items.
    /// Phase A deduplicates exact wire-copy duplicates across sources.
    /// Phase B clusters remaining articles about the same story.
    func clusterRecentItems() {
        let cutoff = Date().addingTimeInterval(-Self.clusterWindowSeconds)
        let items = store.fetchRecentItems(since: cutoff)
        let sourceCount = Set(items.map(\.sourceID)).count
        logger.info("Clustering: \(items.count) items from \(sourceCount) sources in 12h window")
        guard items.count >= 2 else {
            logger.info("Clustering: skipped — fewer than 2 items")
            return
        }

        // Clear stale clusters outside the window
        store.clearClusterFields(olderThan: cutoff)

        // ── Phase A: Dedup exact duplicates ──
        let dedupedItems = deduplicateExactTitles(items)
        if dedupedItems.count < items.count {
            logger.info("Clustering: deduped \(items.count - dedupedItems.count) exact duplicates, \(dedupedItems.count) remain")
        }

        // ── Phase B: Cluster same-story, different-coverage articles ──

        // Pass 1a — SimHash candidate pairs (cheap, catches near-identical titles)
        let simhashPairs = findSimHashCandidates(dedupedItems)
        logger.info("Pass 1a (SimHash): \(simhashPairs.count) candidate pairs")

        // Pass 1b — Temporal candidates (catches differently-worded same-story
        // articles that SimHash misses). The embedding model filters false
        // positives in Pass 2, so a loose candidate set is safe.
        let simhashIndices = Set(simhashPairs.flatMap { [$0.0, $0.1] })
        let unmatchedItems = dedupedItems.enumerated()
            .filter { !simhashIndices.contains($0.offset) }
            .map { $0.element }
        let temporalPairs = findTemporalCandidates(unmatchedItems, allItems: dedupedItems)
        logger.info("Pass 1b (Temporal): \(temporalPairs.count) candidate pairs")

        // Cap total candidates at 200 to prevent the 2000+ candidate explosion
        // that causes 3-5 second pipeline times. Prioritize simhash pairs (higher
        // signal) and take a random sample of temporal pairs if needed.
        let maxCandidates = 200
        let candidatePairs: [(Int, Int)]
        if simhashPairs.count + temporalPairs.count > maxCandidates {
            let temporalBudget = max(0, maxCandidates - simhashPairs.count)
            let sampledTemporal = Array(temporalPairs.shuffled().prefix(temporalBudget))
            candidatePairs = simhashPairs + sampledTemporal
            logger.info("Capped candidates: \(simhashPairs.count) simhash + \(sampledTemporal.count) temporal (dropped \(temporalPairs.count - sampledTemporal.count) temporal)")
        } else {
            candidatePairs = simhashPairs + temporalPairs
        }
        guard !candidatePairs.isEmpty else {
            logger.info("Clustering: no candidates from SimHash or temporal — done")
            return
        }

        // Pass 2 — Sentence embedding on candidates
        let embeddings = computeEmbeddings(for: dedupedItems, candidatePairs: candidatePairs)
        logger.info("Pass 2: computed \(embeddings.count) embeddings")

        let pass2Pairs = filterByEmbeddingSimilarity(
            candidatePairs: candidatePairs,
            items: dedupedItems,
            embeddings: embeddings
        )
        logger.info("Pass 2 (Embedding ≥ 0.72): \(pass2Pairs.count) pairs survived")

        guard !pass2Pairs.isEmpty else {
            logger.info("Clustering: no pairs passed embedding threshold — done")
            return
        }

        // Pass 3 — NER entity overlap (skipped for high-confidence embeddings)
        let confirmedPairs = filterByNEROverlap(
            pass2Pairs,
            items: dedupedItems,
            embeddings: embeddings
        )
        logger.info("Pass 3 (NER): \(confirmedPairs.count) pairs confirmed")

        guard !confirmedPairs.isEmpty else {
            logger.info("Clustering: no pairs passed NER gate — done")
            return
        }

        // Resolve clusters
        let clusters = resolveClusters(confirmedPairs, items: dedupedItems)
        logger.info("Resolved \(clusters.count) clusters")

        // Persist cluster assignments
        persistClusters(clusters, items: dedupedItems)
    }

    // MARK: - Phase A: Exact Duplicate Dedup

    /// Deduplicates articles with identical (or near-identical) titles from
    /// different sources. Keeps the article from the highest-affinity source
    /// and hides the rest by setting `river_visible = 0`.
    ///
    /// Returns the filtered item list with duplicates removed.
    private func deduplicateExactTitles(_ items: [FeedItem]) -> [FeedItem] {
        // Group by lowercased title
        var titleGroups: [String: [FeedItem]] = [:]
        for item in items {
            let key = item.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            titleGroups[key, default: []].append(item)
        }

        var toHide: [UUID] = []
        var survivorIDs = Set<UUID>()

        for (_, group) in titleGroups {
            if group.count == 1 {
                // Only one article with this title — nothing to dedup
                survivorIDs.insert(group[0].id)
                continue
            }

            // Multiple articles share the same title. Keep the one with the
            // highest relevance score, hide the rest.
            let sorted = group.sorted { $0.relevanceScore > $1.relevanceScore }
            survivorIDs.insert(sorted[0].id)
            for duplicate in sorted.dropFirst() {
                toHide.append(duplicate.id)
            }
        }

        if !toHide.isEmpty {
            store.setRiverVisible(false, forItemIDs: toHide)
        }

        return items.filter { survivorIDs.contains($0.id) }
    }

    // MARK: - Pass 1: SimHash Candidates

    /// Finds cross-source pairs of items with SimHash hamming distance <= threshold.
    /// Same-source items are never clustered — clustering is for grouping coverage
    /// of the same story across different news outlets.
    private func findSimHashCandidates(_ items: [FeedItem]) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                // Skip same-source pairs — clustering is cross-source only
                guard items[i].sourceID != items[j].sourceID else { continue }
                let dist = SimHash.hammingDistance(items[i].simhashValue, items[j].simhashValue)
                if dist <= Self.simhashThreshold {
                    pairs.append((i, j))
                }
            }
        }
        return pairs
    }

    // MARK: - Temporal Candidates

    /// Finds cross-source pairs of unmatched items that are temporally proximate (within 6 hours).
    /// This catches same-story articles that have very different wording (high SimHash distance)
    /// but were published around the same time by different outlets.
    private func findTemporalCandidates(
        _ unmatched: [FeedItem],
        allItems: [FeedItem]
    ) -> [(Int, Int)] {
        guard unmatched.count >= 2 else { return [] }

        // Build index mapping from item ID to its position in allItems
        var indexMap: [UUID: Int] = [:]
        for (idx, item) in allItems.enumerated() {
            indexMap[item.id] = idx
        }

        var pairs: [(Int, Int)] = []
        let sixHours: TimeInterval = 6 * 3600

        for i in 0..<unmatched.count {
            for j in (i + 1)..<unmatched.count {
                // Cross-source only
                guard unmatched[i].sourceID != unmatched[j].sourceID else { continue }
                let timeDiff = abs(unmatched[i].publishedAt.timeIntervalSince(unmatched[j].publishedAt))
                if timeDiff <= sixHours,
                   let idxI = indexMap[unmatched[i].id],
                   let idxJ = indexMap[unmatched[j].id] {
                    pairs.append((idxI, idxJ))
                }
            }
        }
        return pairs
    }

    // MARK: - Pass 2: Sentence Embedding

    /// Computes sentence embeddings for items that appear in candidate pairs.
    private func computeEmbeddings(
        for items: [FeedItem],
        candidatePairs: [(Int, Int)]
    ) -> [Int: [Float]] {
        guard let provider = embeddingProvider else { return [:] }

        // Collect unique indices that need embeddings
        var neededIndices = Set<Int>()
        for (i, j) in candidatePairs {
            neededIndices.insert(i)
            neededIndices.insert(j)
        }

        var results: [Int: [Float]] = [:]
        for idx in neededIndices {
            let item = items[idx]

            // Use cached embedding if available (same provider — validated at init)
            if let cached = item.embeddingVector, cached.count == provider.dimensions {
                results[idx] = cached
                continue
            }

            // Compute embedding from title + description excerpt (max 200 chars)
            let text = embeddingText(for: item)
            if let vector = provider.embed(text) {
                results[idx] = vector
                store.updateEmbeddingVector(itemID: item.id, vector: vector)
            }
        }
        return results
    }

    /// Constructs the text used for embedding: title + excerpt, capped at 200 chars.
    private func embeddingText(for item: FeedItem) -> String {
        let combined = item.title + " " + item.excerpt
        if combined.count <= 200 {
            return combined
        }
        return String(combined.prefix(200))
    }

    /// Filters candidate pairs by cosine similarity of their embeddings.
    private func filterByEmbeddingSimilarity(
        candidatePairs: [(Int, Int)],
        items: [FeedItem],
        embeddings: [Int: [Float]]
    ) -> [(Int, Int)] {
        candidatePairs.filter { (i, j) in
            guard let vecA = embeddings[i], let vecB = embeddings[j] else { return false }
            return Self.cosineSimilarity(vecA, vecB) >= Self.embeddingSimilarityThreshold
        }
    }

    /// Cosine similarity between two float vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot  = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    // MARK: - Pass 3: NER Entity Overlap

    /// Filters pairs by shared named entities, with a bypass for high-confidence
    /// embedding scores. When cosine similarity >= 0.75, the pair is confirmed
    /// without NER — the semantic signal is strong enough on its own.
    private func filterByNEROverlap(
        _ pairs: [(Int, Int)],
        items: [FeedItem],
        embeddings: [Int: [Float]]
    ) -> [(Int, Int)] {
        // Cache entity extraction per item index
        var entityCache: [Int: Set<String>] = [:]

        func entities(for idx: Int) -> Set<String> {
            if let cached = entityCache[idx] { return cached }
            let result = extractEntities(from: items[idx])
            entityCache[idx] = result
            return result
        }

        return pairs.filter { (i, j) in
            // High-confidence embeddings bypass NER entirely
            if let vecA = embeddings[i], let vecB = embeddings[j] {
                let similarity = Self.cosineSimilarity(vecA, vecB)
                if similarity >= Self.highConfidenceEmbeddingThreshold {
                    return true
                }
            }

            // Borderline embedding scores require NER confirmation
            let entitiesA = entities(for: i)
            let entitiesB = entities(for: j)
            let shared = entitiesA.intersection(entitiesB)
            return shared.count >= Self.minSharedEntities
        }
    }

    /// Extracts named entities (person, place, organization) from title + excerpt.
    private func extractEntities(from item: FeedItem) -> Set<String> {
        let text = item.title + ". " + String(item.excerpt.prefix(300))
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities = Set<String>()
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        let tags: [NLTag] = [.personalName, .placeName, .organizationName]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            if let tag, tags.contains(tag) {
                let entity = String(text[range]).lowercased().trimmingCharacters(in: .whitespaces)
                if entity.count > 1 {
                    entities.insert(entity)
                }
            }
            return true
        }
        return entities
    }

    // MARK: - Cluster Resolution

    /// Groups confirmed pairs into clusters using union-find.
    private func resolveClusters(
        _ pairs: [(Int, Int)],
        items: [FeedItem]
    ) -> [[Int]] {
        // Union-Find
        var parent = Array(0..<items.count)

        func find(_ x: Int) -> Int {
            if parent[x] != x {
                parent[x] = find(parent[x])
            }
            return parent[x]
        }

        func union(_ x: Int, _ y: Int) {
            let px = find(x)
            let py = find(y)
            if px != py { parent[px] = py }
        }

        for (i, j) in pairs {
            union(i, j)
        }

        // Group by root
        var groups: [Int: [Int]] = [:]
        for (i, j) in pairs {
            let root = find(i)
            if groups[root] == nil { groups[root] = [] }
            // Add both indices (dedup via Set later)
        }

        // Collect all indices that are part of any pair
        var memberIndices = Set<Int>()
        for (i, j) in pairs {
            memberIndices.insert(i)
            memberIndices.insert(j)
        }

        // Group by root
        var clusterMap: [Int: Set<Int>] = [:]
        for idx in memberIndices {
            let root = find(idx)
            clusterMap[root, default: []].insert(idx)
        }

        // Only return clusters with 2+ items
        return clusterMap.values
            .map { Array($0).sorted() }
            .filter { $0.count >= 2 }
    }

    // MARK: - Persistence

    /// Assigns clusterID and isCanonical to items and persists to SQLite.
    private func persistClusters(_ clusters: [[Int]], items: [FeedItem]) {
        for memberIndices in clusters {
            let clusterID = UUID()
            let clusterItems = memberIndices.map { items[$0] }

            // Canonical = earliest published, or highest-affinity source
            let canonical = selectCanonical(from: clusterItems)

            var updates: [(id: UUID, clusterID: UUID, isCanonical: Bool)] = []
            for item in clusterItems {
                updates.append((
                    id: item.id,
                    clusterID: clusterID,
                    isCanonical: item.id == canonical.id
                ))
            }

            store.updateClusterAssignments(updates)
        }
    }

    /// Selects the canonical item: prefer source with affinity > 0.5, fallback to earliest published.
    private func selectCanonical(from items: [FeedItem]) -> FeedItem {
        // Check if any source has high affinity
        for item in items {
            if let record = store.fetchAffinity(forSource: item.sourceID),
               record.affinityScore > 0.5 {
                return item
            }
        }
        // Fallback: earliest published
        return items.min(by: { $0.publishedAt < $1.publishedAt }) ?? items[0]
    }
}
