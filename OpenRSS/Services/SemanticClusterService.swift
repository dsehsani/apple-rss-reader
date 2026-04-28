//
//  SemanticClusterService.swift
//  OpenRSS
//
//  Phase 2b — Stage 2 of the River Pipeline.
//  Three-pass clustering system that groups related news stories:
//    Pass 1: SimHash on title tokens (cheap, runs on all items)
//    Pass 2: NLEmbedding on candidate pairs (expensive, targeted)
//    Pass 3: NER entity overlap on Pass 2 survivors (confirmation)
//
//  Only clusters items within a 6-hour window.
//

import Foundation
import NaturalLanguage

// MARK: - SemanticClusterService

final class SemanticClusterService: Sendable {

    // MARK: - Dependencies

    private let store = SQLiteStore.shared

    // MARK: - Configuration

    /// Maximum age (in seconds) for items to be considered for clustering.
    private static let clusterWindowSeconds: TimeInterval = 6 * 3600

    /// SimHash hamming distance threshold for Pass 1 candidates.
    private static let simhashThreshold = 3

    /// Cosine similarity threshold for Pass 2 embedding comparison.
    private static let embeddingSimilarityThreshold: Float = 0.82

    /// Minimum shared NER entities for Pass 3 confirmation.
    private static let minSharedEntities = 2

    // MARK: - Public API

    /// Runs the three-pass clustering pipeline on recent items.
    /// Updates cluster_id and is_canonical fields in SQLite.
    func clusterRecentItems() {
        let cutoff = Date().addingTimeInterval(-Self.clusterWindowSeconds)
        let items = store.fetchRecentItems(since: cutoff)
        guard items.count >= 2 else { return }

        // Clear stale clusters outside the window
        store.clearClusterFields(olderThan: cutoff)

        // Pass 1 — SimHash candidate pairs
        let pass1Pairs = findSimHashCandidates(items)

        // Collect unique item IDs that are part of Pass 1 pairs
        var pass1ItemIDs = Set<UUID>()
        for (i, j) in pass1Pairs {
            pass1ItemIDs.insert(items[i].id)
            pass1ItemIDs.insert(items[j].id)
        }

        // Also include temporally proximate items with no Pass 1 match
        // (items within 6-hour window that didn't get a SimHash candidate)
        let unmatched = items.filter { !pass1ItemIDs.contains($0.id) }
        let temporalCandidates = findTemporalCandidates(unmatched, allItems: items)

        // Merge candidate pairs
        let allCandidatePairs = pass1Pairs + temporalCandidates

        guard !allCandidatePairs.isEmpty else { return }

        // Pass 2 — NLEmbedding on candidates
        let embeddings = computeEmbeddings(for: items, candidatePairs: allCandidatePairs)
        let pass2Pairs = filterByEmbeddingSimilarity(
            candidatePairs: allCandidatePairs,
            items: items,
            embeddings: embeddings
        )

        guard !pass2Pairs.isEmpty else { return }

        // Pass 3 — NER entity overlap
        let confirmedPairs = filterByNEROverlap(pass2Pairs, items: items)

        guard !confirmedPairs.isEmpty else { return }

        // Resolve clusters
        let clusters = resolveClusters(confirmedPairs, items: items)

        // Persist cluster assignments
        persistClusters(clusters, items: items)
    }

    // MARK: - Pass 1: SimHash Candidates

    /// Finds pairs of items with SimHash hamming distance <= threshold.
    private func findSimHashCandidates(_ items: [FeedItem]) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let dist = SimHash.hammingDistance(items[i].simhashValue, items[j].simhashValue)
                if dist <= Self.simhashThreshold {
                    pairs.append((i, j))
                }
            }
        }
        return pairs
    }

    // MARK: - Temporal Candidates

    /// Finds pairs of unmatched items that are temporally proximate (within 2 hours).
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
        let twoHours: TimeInterval = 2 * 3600

        for i in 0..<unmatched.count {
            for j in (i + 1)..<unmatched.count {
                let timeDiff = abs(unmatched[i].publishedAt.timeIntervalSince(unmatched[j].publishedAt))
                if timeDiff <= twoHours,
                   let idxI = indexMap[unmatched[i].id],
                   let idxJ = indexMap[unmatched[j].id] {
                    pairs.append((idxI, idxJ))
                }
            }
        }
        return pairs
    }

    // MARK: - Pass 2: NLEmbedding

    /// Computes sentence embeddings for items that appear in candidate pairs.
    private func computeEmbeddings(
        for items: [FeedItem],
        candidatePairs: [(Int, Int)]
    ) -> [Int: [Float]] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return [:]
        }

        // Collect unique indices that need embeddings
        var neededIndices = Set<Int>()
        for (i, j) in candidatePairs {
            neededIndices.insert(i)
            neededIndices.insert(j)
        }

        var results: [Int: [Float]] = [:]
        for idx in neededIndices {
            let item = items[idx]

            // Use cached embedding if available
            if let cached = item.embeddingVector {
                results[idx] = cached
                continue
            }

            // Compute embedding from title + description excerpt (max 200 chars)
            let text = embeddingText(for: item)
            if let vector = embedding.vector(for: text) {
                let floatVector = vector.map { Float($0) }
                results[idx] = floatVector

                // Store the embedding vector for reuse within the window
                store.updateEmbeddingVector(itemID: item.id, vector: floatVector)
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

    /// Filters pairs by requiring >= 2 shared named entities.
    private func filterByNEROverlap(
        _ pairs: [(Int, Int)],
        items: [FeedItem]
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
