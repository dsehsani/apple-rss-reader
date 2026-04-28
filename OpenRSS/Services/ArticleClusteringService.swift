//
//  ArticleClusteringService.swift
//  OpenRSS
//
//  Clusters related articles using Apple's NaturalLanguage framework.
//  Two passes: cross-source deduplication, then intra-source burst grouping.
//  Graceful fallback chain: sentence embedding → word-average → Jaccard bigrams.
//

import Foundation
import NaturalLanguage
import os

private let logger = Logger(subsystem: "com.openrss", category: "Clustering")

final class ArticleClusteringService {

    // MARK: - Singleton

    static let shared = ArticleClusteringService()

    // MARK: - Thresholds

    /// Cosine similarity threshold for embedding-based comparison.
    private let embeddingThreshold: Double = 0.62

    /// Jaccard threshold for the bigram fallback (lower because bigrams are less precise).
    private let jaccardThreshold: Double = 0.65

    /// Maximum time window (hours) for pairwise comparison between two articles.
    private let temporalWindowHours: Double = 6.0

    // MARK: - Embedders

    /// Preferred sentence-level embedder.
    private lazy var sentenceEmbedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    /// Fallback word-level embedder used if sentence embedding is unavailable.
    private lazy var wordEmbedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

    /// Diagnostics string describing which method is active.
    var clusteringMethod: String {
        if sentenceEmbedding != nil { return "NLEmbedding (sentence)" }
        if wordEmbedding != nil     { return "NLEmbedding (word-average)" }
        return "Jaccard bigrams (fallback)"
    }

    // MARK: - Init

    private init() {
        logger.info("Clustering method: \(self.clusteringMethod, privacy: .public)")
    }

    // MARK: - Similarity

    enum SimilarityMethod {
        case sentence
        case word
        case jaccard
    }

    struct SimilarityResult {
        let score: Double
        let method: SimilarityMethod
    }

    /// Returns the similarity score and which method produced it.
    private func score(_ titleA: String, _ titleB: String) -> SimilarityResult {
        let a = titleA.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = titleB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else {
            return SimilarityResult(score: 0, method: .jaccard)
        }

        // Step 1: sentence embedding
        if let embedder = sentenceEmbedding {
            if let va = embedder.vector(for: a), let vb = embedder.vector(for: b) {
                return SimilarityResult(score: cosine(va, vb), method: .sentence)
            }
        }

        // Step 2: word embedding fallback (average word vectors)
        if let embedder = wordEmbedding {
            if let va = averagedWordVector(for: a, embedder: embedder),
               let vb = averagedWordVector(for: b, embedder: embedder) {
                return SimilarityResult(score: cosine(va, vb), method: .word)
            }
        }

        // Step 3: Jaccard bigrams
        return SimilarityResult(score: jaccardBigrams(a, b), method: .jaccard)
    }

    /// Returns the threshold appropriate for a given method.
    private func threshold(for method: SimilarityMethod) -> Double {
        switch method {
        case .sentence, .word: return embeddingThreshold
        case .jaccard:         return jaccardThreshold
        }
    }

    // MARK: - Vector Helpers

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, magA = 0.0, magB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = sqrt(magA) * sqrt(magB)
        guard denom > 0 else { return 0 }
        return max(0, min(1, dot / denom))
    }

    private func averagedWordVector(for text: String, embedder: NLEmbedding) -> [Double]? {
        let words = tokenize(text)
        guard !words.isEmpty else { return nil }

        var accum: [Double] = []
        var count = 0
        for word in words {
            guard let vec = embedder.vector(for: word) else { continue }
            if accum.isEmpty {
                accum = vec
            } else if accum.count == vec.count {
                for i in accum.indices { accum[i] += vec[i] }
            }
            count += 1
        }
        guard count > 0 else { return nil }
        for i in accum.indices { accum[i] /= Double(count) }
        return accum
    }

    // MARK: - Jaccard Fallback

    private func jaccardBigrams(_ a: String, _ b: String) -> Double {
        let wordsA = normalizedWords(a)
        let wordsB = normalizedWords(b)
        let bigramsA = bigrams(from: wordsA)
        let bigramsB = bigrams(from: wordsB)
        let union = bigramsA.union(bigramsB)
        guard !union.isEmpty else { return 0 }
        let intersection = bigramsA.intersection(bigramsB)
        return Double(intersection.count) / Double(union.count)
    }

    private func normalizedWords(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(allowed)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private func bigrams(from words: [String]) -> Set<String> {
        guard words.count >= 2 else { return Set(words) }
        var out = Set<String>()
        for i in 0..<(words.count - 1) {
            out.insert("\(words[i]) \(words[i + 1])")
        }
        return out
    }

    private func tokenize(_ text: String) -> [String] {
        normalizedWords(text)
    }

    // MARK: - Temporal Window

    private func isWithinTemporalWindow(_ a: Article, _ b: Article) -> Bool {
        abs(a.publishedAt.timeIntervalSince(b.publishedAt)) <= temporalWindowHours * 3600
    }

    // MARK: - Main Clustering Method

    /// Mutates `articles` in place, assigning `clusterID`, `clusterSize`, and `isCanonical`.
    func clusterArticles(_ articles: inout [Article]) {
        // Reset every article to defaults for a clean slate.
        for i in articles.indices {
            articles[i].clusterID = nil
            articles[i].clusterSize = 1
            articles[i].isCanonical = true
        }

        // Determine eligible indices: non-empty title, not archived.
        var eligibleIndices: [Int] = []
        for i in articles.indices {
            let a = articles[i]
            guard !a.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !a.isArchived else { continue }
            eligibleIndices.append(i)
        }

        // Performance guard: restrict pairwise to last 48h for large sets.
        if articles.count > 500 {
            let cutoff = Date().addingTimeInterval(-48 * 3600)
            eligibleIndices = eligibleIndices.filter { articles[$0].publishedAt >= cutoff }
        }

        eligibleIndices.sort { articles[$0].publishedAt > articles[$1].publishedAt }

        // Pass 1: cross-source clustering (deduplication)
        var clusterMap: [Int: UUID] = [:]
        var clusterMembers: [UUID: [Int]] = [:]

        for outerPos in 0..<eligibleIndices.count {
            let i = eligibleIndices[outerPos]
            for innerPos in (outerPos + 1)..<eligibleIndices.count {
                let j = eligibleIndices[innerPos]

                guard articles[i].sourceID != articles[j].sourceID else { continue }
                guard isWithinTemporalWindow(articles[i], articles[j]) else { continue }

                let result = score(articles[i].title, articles[j].title)
                let t = threshold(for: result.method)

                if result.score >= t {
                    let cid = clusterMap[i] ?? clusterMap[j] ?? UUID()
                    if clusterMap[i] == nil {
                        clusterMap[i] = cid
                        clusterMembers[cid, default: []].append(i)
                    }
                    if clusterMap[j] == nil {
                        clusterMap[j] = cid
                        clusterMembers[cid, default: []].append(j)
                    }
                }
            }
        }

        // Apply cross-source: canonical = longest excerpt, tiebreak earliest publishedAt
        var clusteredIndices = Set<Int>()
        for (cid, members) in clusterMembers where members.count > 1 {
            let canonical = members.min { a, b in
                let ea = articles[a].excerpt.count
                let eb = articles[b].excerpt.count
                if ea != eb { return ea > eb }
                return articles[a].publishedAt < articles[b].publishedAt
            }!
            for idx in members {
                articles[idx].clusterID = cid
                articles[idx].isCanonical = (idx == canonical)
                clusteredIndices.insert(idx)
            }
            articles[canonical].clusterSize = members.count
        }

        // Pass 2: intra-source burst grouping (only for unclustered)
        let remaining = eligibleIndices.filter { !clusteredIndices.contains($0) }
        let bySource: [UUID: [Int]] = Dictionary(grouping: remaining) { articles[$0].sourceID }

        for (_, indices) in bySource {
            guard indices.count >= 2 else { continue }
            let sortedIndices = indices.sorted { articles[$0].publishedAt < articles[$1].publishedAt }

            var groups: [[Int]] = []
            var currentGroup: [Int] = []

            for idx in sortedIndices {
                if currentGroup.isEmpty {
                    currentGroup = [idx]
                    continue
                }

                var matched = false
                for memberIdx in currentGroup {
                    guard isWithinTemporalWindow(articles[idx], articles[memberIdx]) else { continue }
                    let result = score(articles[idx].title, articles[memberIdx].title)
                    let t = threshold(for: result.method)
                    if result.score >= t {
                        matched = true
                        break
                    }
                }

                if matched {
                    currentGroup.append(idx)
                } else {
                    if currentGroup.count >= 2 { groups.append(currentGroup) }
                    currentGroup = [idx]
                }
            }
            if currentGroup.count >= 2 { groups.append(currentGroup) }

            for group in groups {
                let cid = UUID()
                let canonical = group.min { a, b in
                    articles[a].title.count > articles[b].title.count
                }!
                for idx in group {
                    articles[idx].clusterID = cid
                    articles[idx].isCanonical = (idx == canonical)
                }
                articles[canonical].clusterSize = group.count
            }
        }

        let clusterCount = articles.filter { $0.clusterID != nil }.count
        let totalCount = articles.count
        let method = self.clusteringMethod
        logger.info("Clustering complete: \(clusterCount, privacy: .public) clustered articles from \(totalCount, privacy: .public) total using \(method, privacy: .public)")
    }
}
