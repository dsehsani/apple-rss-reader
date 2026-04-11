//
//  ArticleClusteringService.swift
//  OpenRSS
//
//  Clusters related articles using Apple's NaturalLanguage framework.
//  Two passes: cross-source deduplication, then intra-source burst grouping.
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
    ///
    /// NLEmbedding's sentence embeddings score paraphrases more conservatively
    /// than typical cosine intuitions suggest — real duplicate headlines routinely
    /// land in the 0.60–0.75 range, not 0.80+. Empirically tuned against a sample
    /// of TechCrunch/NYT/etc. feeds where the obvious "same story" pair scored 0.661
    /// and the next-highest unrelated pair scored 0.531, giving a wide safety margin.
    private let embeddingThreshold: Double = 0.62

    /// Jaccard threshold for the bigram fallback (lower because bigrams are less precise).
    private let jaccardThreshold: Double = 0.65

    /// Maximum time window (hours) for PAIRWISE comparison between two articles.
    /// This is NOT an eligibility filter — articles from any age can cluster as long as
    /// their publishedAt values are within this window of each other.
    private let temporalWindowHours: Double = 6.0

    // MARK: - Diagnostics

    /// When true, `clusterArticles` emits a detailed breakdown of what happened:
    /// counts at each gate, final cluster count, and the top near-miss pairs
    /// that *almost* clustered. Toggle off for production.
    var debugLogging: Bool = true

    /// One entry in the near-miss leaderboard.
    private struct NearMiss {
        let score: Double
        let method: SimilarityMethod
        let threshold: Double
        let hoursApart: Double
        let titleA: String
        let titleB: String
        let sameSource: Bool
    }

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

    /// Pairwise similarity between two article titles. Exposed as `internal`
    /// (not `private`) so debug code or tests can exercise it directly.
    func similarity(between a: Article, and b: Article) -> Double {
        score(a.title, b.title).score
    }

    /// Returns the similarity score *and* which method produced it, so the
    /// caller can pick the appropriate threshold.
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
            // fall through
        }

        // Step 2: word embedding fallback (average word vectors)
        if let embedder = wordEmbedding {
            if let va = averagedWordVector(for: a, embedder: embedder),
               let vb = averagedWordVector(for: b, embedder: embedder) {
                return SimilarityResult(score: cosine(va, vb), method: .word)
            }
            // fall through
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

    /// Mutates `articles` in place, assigning `clusterID`, `clusterSize`, and
    /// `isCanonical`. Safe to call on a freshly loaded or freshly refreshed array.
    ///
    /// Note: categoryID is intentionally ignored. Stories that cross folder boundaries
    /// still cluster; the canonical article's categoryID determines folder visibility.
    func clusterArticles(_ articles: inout [Article]) {
        // Diagnostic counters (only used when debugLogging is on).
        var pass1Compared = 0
        var pass1WithinWindow = 0
        var pass1HitThreshold = 0
        var pass1MethodCounts: [SimilarityMethod: Int] = [:]
        var pass2Compared = 0
        var pass2WithinWindow = 0
        var pass2HitThreshold = 0
        var nearMisses: [NearMiss] = []

        /// Keeps the top 10 highest-scoring non-matching pairs for diagnostics.
        func recordNearMiss(_ nm: NearMiss) {
            guard debugLogging else { return }
            nearMisses.append(nm)
            if nearMisses.count > 30 {
                nearMisses.sort { $0.score > $1.score }
                nearMisses = Array(nearMisses.prefix(10))
            }
        }

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

        // Performance guard: if there are too many articles, restrict pairwise
        // passes to those within the last 48 hours. Older articles stay at
        // their default (standalone) values.
        if articles.count > 500 {
            let cutoff = Date().addingTimeInterval(-48 * 3600)
            eligibleIndices = eligibleIndices.filter { articles[$0].publishedAt >= cutoff }
        }

        // Sort eligible by publishedAt descending
        eligibleIndices.sort { articles[$0].publishedAt > articles[$1].publishedAt }

        // Pass 1: cross-source clustering (deduplication)
        var clusterMap: [Int: UUID] = [:] // index -> cluster id
        var clusterMembers: [UUID: [Int]] = [:]

        for outerPos in 0..<eligibleIndices.count {
            let i = eligibleIndices[outerPos]
            for innerPos in (outerPos + 1)..<eligibleIndices.count {
                let j = eligibleIndices[innerPos]

                // Different source only
                guard articles[i].sourceID != articles[j].sourceID else { continue }
                pass1Compared += 1
                // Pairwise time window
                guard isWithinTemporalWindow(articles[i], articles[j]) else { continue }
                pass1WithinWindow += 1

                let result = score(articles[i].title, articles[j].title)
                let t = threshold(for: result.method)
                pass1MethodCounts[result.method, default: 0] += 1

                if result.score >= t {
                    pass1HitThreshold += 1
                    let cid = clusterMap[i] ?? clusterMap[j] ?? UUID()
                    if clusterMap[i] == nil {
                        clusterMap[i] = cid
                        clusterMembers[cid, default: []].append(i)
                    }
                    if clusterMap[j] == nil {
                        clusterMap[j] = cid
                        clusterMembers[cid, default: []].append(j)
                    }
                } else if debugLogging && result.score > 0 {
                    let hours = abs(articles[i].publishedAt.timeIntervalSince(articles[j].publishedAt)) / 3600
                    recordNearMiss(NearMiss(
                        score: result.score,
                        method: result.method,
                        threshold: t,
                        hoursApart: hours,
                        titleA: articles[i].title,
                        titleB: articles[j].title,
                        sameSource: false
                    ))
                }
            }
        }

        // Apply cross-source cluster results: canonical = longest excerpt, tiebreak earliest publishedAt
        var clusteredIndices = Set<Int>()
        for (cid, members) in clusterMembers where members.count > 1 {
            let canonical = members.min { a, b in
                let ea = articles[a].excerpt.count
                let eb = articles[b].excerpt.count
                if ea != eb { return ea > eb } // longest first
                return articles[a].publishedAt < articles[b].publishedAt // earliest tiebreak
            }!
            for idx in members {
                articles[idx].clusterID = cid
                articles[idx].isCanonical = (idx == canonical)
                clusteredIndices.insert(idx)
            }
            articles[canonical].clusterSize = members.count
        }

        // Pass 2: intra-source burst grouping (only for articles not yet clustered)
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

                // Compare against every member in the current group using the pairwise
                // window and similarity. If any member matches, add this one.
                var matched = false
                for memberIdx in currentGroup {
                    pass2Compared += 1
                    guard isWithinTemporalWindow(articles[idx], articles[memberIdx]) else { continue }
                    pass2WithinWindow += 1
                    let result = score(articles[idx].title, articles[memberIdx].title)
                    let t = threshold(for: result.method)
                    if result.score >= t {
                        pass2HitThreshold += 1
                        matched = true
                        break
                    } else if debugLogging && result.score > 0 {
                        let hours = abs(articles[idx].publishedAt.timeIntervalSince(articles[memberIdx].publishedAt)) / 3600
                        recordNearMiss(NearMiss(
                            score: result.score,
                            method: result.method,
                            threshold: t,
                            hoursApart: hours,
                            titleA: articles[idx].title,
                            titleB: articles[memberIdx].title,
                            sameSource: true
                        ))
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

            // Apply intra-source cluster results: canonical = longest title
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

        // MARK: Diagnostics summary

        if debugLogging {
            // Copy values into locals — logger.info's interpolation is an escaping
            // autoclosure and cannot capture the `inout articles` parameter directly.
            let totalCount = articles.count
            let eligibleCount = eligibleIndices.count
            let finalClusters = Dictionary(grouping: articles.filter { $0.clusterID != nil }, by: { $0.clusterID! })
            let crossSourceGroupCount = finalClusters.values.filter { group in
                Set(group.map(\.sourceID)).count > 1
            }.count
            let sameSourceGroupCount = finalClusters.values.filter { group in
                Set(group.map(\.sourceID)).count == 1
            }.count
            let clusteredArticleCount = finalClusters.values.map(\.count).reduce(0, +)
            let finalClusterCount = finalClusters.count

            let methodSummary = pass1MethodCounts
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: " ")

            logger.info("""
            === Clustering summary ===
            total articles: \(totalCount, privacy: .public)
            eligible: \(eligibleCount, privacy: .public)
            method: \(self.clusteringMethod, privacy: .public)
            ---
            Pass 1 (cross-source): compared=\(pass1Compared, privacy: .public) withinWindow=\(pass1WithinWindow, privacy: .public) hitThreshold=\(pass1HitThreshold, privacy: .public) [\(methodSummary, privacy: .public)]
            Pass 2 (same-source):  compared=\(pass2Compared, privacy: .public) withinWindow=\(pass2WithinWindow, privacy: .public) hitThreshold=\(pass2HitThreshold, privacy: .public)
            ---
            final clusters: \(finalClusterCount, privacy: .public) (cross-source=\(crossSourceGroupCount, privacy: .public), same-source=\(sameSourceGroupCount, privacy: .public))
            articles inside clusters: \(clusteredArticleCount, privacy: .public)
            """)

            // Top 10 near-misses — pairs that almost clustered.
            let topMisses = nearMisses.sorted { $0.score > $1.score }.prefix(10)
            if topMisses.isEmpty {
                logger.info("No near-miss pairs recorded (no pair within 6h produced a nonzero similarity score).")
            } else {
                logger.info("--- Top \(topMisses.count, privacy: .public) near-miss pairs ---")
                for (n, nm) in topMisses.enumerated() {
                    let srcTag = nm.sameSource ? "same" : "cross"
                    let hoursStr = String(format: "%.1fh", nm.hoursApart)
                    let scoreStr = String(format: "%.3f", nm.score)
                    let threshStr = String(format: "%.2f", nm.threshold)
                    let titleA = nm.titleA.prefix(70)
                    let titleB = nm.titleB.prefix(70)
                    logger.info("  #\(n + 1, privacy: .public) [\(srcTag, privacy: .public)] score=\(scoreStr, privacy: .public)/\(threshStr, privacy: .public) method=\(String(describing: nm.method), privacy: .public) Δt=\(hoursStr, privacy: .public)")
                    logger.info("     A: \(titleA, privacy: .public)")
                    logger.info("     B: \(titleB, privacy: .public)")
                }
            }
        }
    }
}
