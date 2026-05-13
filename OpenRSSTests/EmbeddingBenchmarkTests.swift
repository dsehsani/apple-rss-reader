//
//  EmbeddingBenchmarkTests.swift
//  OpenRSSTests
//
//  Benchmarks comparing CoreML MiniLM vs NLEmbedding:
//    1. Per-embedding latency
//    2. Batch throughput (simulating a real pipeline cycle)
//    3. Quality comparison on the same article pairs
//

import Testing
import Foundation
@testable import OpenRSS

@Suite("Embedding Benchmarks")
struct EmbeddingBenchmarkTests {

    // MARK: - Test Data

    /// Realistic article titles + excerpts for benchmarking.
    static let articles: [(title: String, excerpt: String)] = [
        ("Apple supplier Foxconn hit by ransomware attack stealing project files",
         "Foxconn confirmed a ransomware cyberattack on its U.S. factories."),
        ("Foxconn confirms ransomware attack affected North American factories",
         "Foxconn acknowledged a ransomware attack that hit its operations."),
        ("Tesla recalls 500,000 vehicles over safety defect in autopilot system",
         "Tesla is recalling half a million cars due to a software bug."),
        ("Ford recalls 300,000 trucks over brake issue in F-150 lineup",
         "Ford Motor Company announced a recall of its popular F-150 trucks."),
        ("NASA launches Artemis IV mission to the Moon",
         "NASA successfully launched the Artemis IV rocket this morning."),
        ("President signs landmark climate bill into law today",
         "The president signed a landmark climate bill setting emissions targets."),
        ("SpaceX successfully lands Starship booster for the first time",
         "SpaceX achieved a historic milestone by landing the booster."),
        ("Google announces Pixel 9 with on-device AI features",
         "Google unveiled its latest Pixel phone with AI capabilities."),
        ("Microsoft acquires gaming studio in $2 billion deal",
         "Microsoft has completed the acquisition of a major game developer."),
        ("Amazon raises Prime subscription price effective next month",
         "Amazon will increase the cost of its Prime membership."),
    ]

    /// Constructs embedding text the same way SemanticClusterService does.
    private static func embeddingText(_ article: (title: String, excerpt: String)) -> String {
        let combined = article.title + " " + article.excerpt
        return combined.count <= 200 ? combined : String(combined.prefix(200))
    }

    // MARK: - Latency Benchmarks

    @Test("CoreML single-embedding latency")
    func coreMLLatency() {
        guard let provider = CoreMLEmbeddingProvider() else {
            Issue.record("CoreML provider unavailable")
            return
        }

        let text = Self.embeddingText(Self.articles[0])

        // Warm up
        _ = provider.embed(text)

        // Measure 10 embeddings
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 10
        for _ in 0..<iterations {
            _ = provider.embed(text)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let perEmbed = elapsed / Double(iterations)

        #expect(perEmbed < 100,
                "CoreML: \(String(format: "%.1f", perEmbed))ms per embedding (target: <100ms on sim, <15ms on device)")
    }

    @Test("NLEmbedding single-embedding latency")
    func nlEmbeddingLatency() {
        guard let provider = NLEmbeddingProvider() else {
            Issue.record("NLEmbedding provider unavailable")
            return
        }

        let text = Self.embeddingText(Self.articles[0])

        // Warm up
        _ = provider.embed(text)

        // Measure 10 embeddings
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 10
        for _ in 0..<iterations {
            _ = provider.embed(text)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let perEmbed = elapsed / Double(iterations)

        #expect(perEmbed < 100,
                "NLEmbedding: \(String(format: "%.1f", perEmbed))ms per embedding")
    }

    // MARK: - Batch Throughput (simulated pipeline)

    @Test("CoreML batch of 10 articles — simulates one pipeline cycle")
    func coreMLBatchThroughput() {
        guard let provider = CoreMLEmbeddingProvider() else {
            Issue.record("CoreML provider unavailable")
            return
        }

        // Warm up
        _ = provider.embed("warmup")

        let texts = Self.articles.map { Self.embeddingText($0) }
        let start = CFAbsoluteTimeGetCurrent()
        for text in texts {
            _ = provider.embed(text)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 1000,
                "CoreML batch of \(texts.count): \(String(format: "%.1f", elapsed))ms total, \(String(format: "%.1f", elapsed / Double(texts.count)))ms/article")
    }

    @Test("NLEmbedding batch of 10 articles — simulates one pipeline cycle")
    func nlEmbeddingBatchThroughput() {
        guard let provider = NLEmbeddingProvider() else {
            Issue.record("NLEmbedding provider unavailable")
            return
        }

        let texts = Self.articles.map { Self.embeddingText($0) }
        let start = CFAbsoluteTimeGetCurrent()
        for text in texts {
            _ = provider.embed(text)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 1000,
                "NLEmbedding batch of \(texts.count): \(String(format: "%.1f", elapsed))ms total, \(String(format: "%.1f", elapsed / Double(texts.count)))ms/article")
    }

    // MARK: - Quality Comparison

    @Test("CoreML quality: same-story vs different-story separation")
    func coreMLQualityReport() {
        guard let provider = CoreMLEmbeddingProvider() else { return }

        let sameStoryA = Self.embeddingText(Self.articles[0])
        let sameStoryB = Self.embeddingText(Self.articles[1])
        let unrelatedA = Self.embeddingText(Self.articles[4])
        let unrelatedB = Self.embeddingText(Self.articles[5])

        guard let vecSA = provider.embed(sameStoryA),
              let vecSB = provider.embed(sameStoryB),
              let vecUA = provider.embed(unrelatedA),
              let vecUB = provider.embed(unrelatedB) else {
            Issue.record("CoreML failed to produce embeddings")
            return
        }

        let sameStorySim = SemanticClusterService.cosineSimilarity(vecSA, vecSB)
        let unrelatedSim = SemanticClusterService.cosineSimilarity(vecUA, vecUB)

        #expect(sameStorySim > unrelatedSim,
                "Same-story similarity (\(sameStorySim)) should exceed unrelated (\(unrelatedSim))")
    }

    @Test("NLEmbedding quality: same-story vs different-story separation")
    func nlEmbeddingQualityReport() {
        guard let provider = NLEmbeddingProvider() else { return }

        let sameStoryA = Self.embeddingText(Self.articles[0])
        let sameStoryB = Self.embeddingText(Self.articles[1])
        let unrelatedA = Self.embeddingText(Self.articles[4])
        let unrelatedB = Self.embeddingText(Self.articles[5])

        guard let vecSA = provider.embed(sameStoryA),
              let vecSB = provider.embed(sameStoryB),
              let vecUA = provider.embed(unrelatedA),
              let vecUB = provider.embed(unrelatedB) else {
            Issue.record("NLEmbedding failed to produce embeddings")
            return
        }

        let sameStorySim = SemanticClusterService.cosineSimilarity(vecSA, vecSB)
        let unrelatedSim = SemanticClusterService.cosineSimilarity(vecUA, vecUB)

        #expect(sameStorySim > unrelatedSim,
                "Same-story similarity (\(sameStorySim)) should exceed unrelated (\(unrelatedSim))")
    }
}
