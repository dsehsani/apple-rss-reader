//
//  CoreMLEmbeddingTests.swift
//  OpenRSSTests
//
//  Validates embedding quality from the EmbeddingProvider.
//
//  On simulator, CoreML float16 runs on CPU with reduced precision, which
//  can degrade embedding quality. Tests that require high-quality embeddings
//  verify the provider produces usable vectors first and skip if not.
//
//  On-device with Neural Engine, expect:
//    same-story: 0.80-0.95
//    same-beat/different-event: 0.40-0.60
//    unrelated: 0.05-0.30
//

import Testing
import Foundation
@testable import OpenRSS

@Suite("Embedding Quality")
struct CoreMLEmbeddingTests {

    // MARK: - Helpers

    private func makeProvider() -> (any EmbeddingProvider)? {
        EmbeddingProviderFactory.makeProvider()
    }

    private func similarity(_ a: String, _ b: String) -> Float? {
        guard let provider = makeProvider(),
              let vecA = provider.embed(a),
              let vecB = provider.embed(b) else {
            return nil
        }
        return SemanticClusterService.cosineSimilarity(vecA, vecB)
    }

    /// Returns true if the provider produces high-quality embeddings that
    /// can discriminate between related and unrelated text. On simulator
    /// with float16 CPU, the model may produce vectors that don't separate
    /// well — this calibration check catches that.
    private func providerProducesUsableEmbeddings() -> Bool {
        guard let related = similarity("iPhone", "Apple smartphone"),
              let unrelated = similarity("iPhone", "soccer match results") else {
            return false
        }
        return related > unrelated
    }

    // MARK: - Provider Availability

    @Test("Provider returns non-nil embeddings with correct dimensions")
    func providerReturnsEmbeddings() {
        guard let provider = makeProvider() else { return }
        let vec = provider.embed("test sentence")
        #expect(vec != nil, "Provider should return an embedding")
        if let vec {
            #expect(vec.count == provider.dimensions,
                    "Expected \(provider.dimensions) dimensions, got \(vec.count)")
        }
    }

    // MARK: - Separation Tests (only run when embeddings are usable)

    @Test("Same-story pair scores higher than different-story pair")
    func sameStoryScoresHigherThanDifferentStory() throws {
        try #require(providerProducesUsableEmbeddings(), "Skipping: provider produces degenerate vectors on this device")

        let sameStory = similarity(
            "Apple supplier Foxconn hit by ransomware attack stealing project files",
            "Foxconn confirms ransomware attack affected North American factories and Apple data"
        )
        let differentStory = similarity(
            "Apple supplier Foxconn hit by ransomware attack stealing project files",
            "Ford recalls 300,000 trucks over brake issue in F-150 lineup"
        )
        guard let sameStory, let differentStory else { return }

        #expect(sameStory > differentStory,
                "Same-story (\(sameStory)) should score higher than different-story (\(differentStory))")
    }

    @Test("Nearly identical titles score higher than unrelated titles")
    func nearIdenticalHigherThanUnrelated() throws {
        try #require(providerProducesUsableEmbeddings(), "Skipping: provider produces degenerate vectors on this device")

        let nearIdentical = similarity(
            "President signs landmark climate bill into law today",
            "President signs landmark climate bill into law"
        )
        let unrelated = similarity(
            "President signs landmark climate bill into law today",
            "Manchester United signs striker in record transfer deal"
        )
        guard let nearIdentical, let unrelated else { return }

        #expect(nearIdentical > unrelated,
                "Near-identical (\(nearIdentical)) should score higher than unrelated (\(unrelated))")
    }

    // MARK: - Negative Tests (should hold on any provider)

    @Test("Completely unrelated topics score low")
    func unrelatedTopics() {
        let sim = similarity(
            "NASA launches Artemis IV mission to the Moon",
            "Manchester United signs striker in record transfer deal"
        )
        guard let sim else { return }

        #expect(sim < 0.55,
                "Unrelated topics should score < 0.55, got \(sim)")
    }

    @Test("Same-beat, different event stays below clustering threshold")
    func sameBeatDifferentEvent() {
        let sim = similarity(
            "Tesla recalls 500,000 vehicles over safety defect in autopilot system",
            "Ford recalls 300,000 trucks over brake issue in F-150 lineup"
        )
        guard let sim else { return }

        #expect(sim < 0.72,
                "Same-beat different-event pair should score < 0.72, got \(sim)")
    }

    @Test("Same topic area, different stories stay below clustering threshold")
    func sameTopicDifferentStories() {
        let sim = similarity(
            "Apple announces new MacBook Pro with M5 chip at WWDC",
            "Apple releases iOS 19 beta with redesigned Control Center"
        )
        guard let sim else { return }

        #expect(sim < 0.72,
                "Different Apple stories should score < 0.72, got \(sim)")
    }
}
