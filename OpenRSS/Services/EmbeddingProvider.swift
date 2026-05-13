//
//  EmbeddingProvider.swift
//  OpenRSS
//
//  Protocol + implementations for sentence embedding.
//  CoreMLEmbeddingProvider uses the bundled all-MiniLM-L6-v2 model.
//  NLEmbeddingProvider wraps Apple's NLEmbedding as a fallback.
//

import CoreML
import Foundation
import NaturalLanguage

// MARK: - Protocol

protocol EmbeddingProvider: Sendable {
    var dimensions: Int { get }
    func embed(_ text: String) -> [Float]?
}

// MARK: - CoreMLEmbeddingProvider

final class CoreMLEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {

    let dimensions = 384
    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let lock = NSLock()

    init?() {
        // Load compiled CoreML model from app bundle
        guard let modelURL = Bundle.main.url(
            forResource: "AllMiniLML6V2",
            withExtension: "mlmodelc"
        ) else {
            return nil
        }

        // Synchronized groups preserve directory structure, so vocab.txt
        // lands under Resources/ML/ in the bundle. Fall back to bundle root
        // in case Xcode flattens it.
        let vocabURL: URL? =
            Bundle.main.url(forResource: "vocab", withExtension: "txt", subdirectory: "Resources/ML")
            ?? Bundle.main.url(forResource: "vocab", withExtension: "txt")
        guard let vocabURL else {
            return nil
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Neural Engine → GPU → CPU
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
            self.tokenizer = try WordPieceTokenizer(vocabURL: vocabURL)
        } catch {
            return nil
        }
    }

    func embed(_ text: String) -> [Float]? {
        let tokens = tokenizer.tokenize(text)

        guard let inputIDsArray = try? MLMultiArray(shape: [1, NSNumber(value: tokenizer.maxLength)], dataType: .int32),
              let maskArray = try? MLMultiArray(shape: [1, NSNumber(value: tokenizer.maxLength)], dataType: .int32)
        else { return nil }

        for i in 0..<tokenizer.maxLength {
            inputIDsArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: tokens.inputIDs[i])
            maskArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: tokens.attentionMask[i])
        }

        let inputFeatures = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])
        guard let inputFeatures else { return nil }

        // MLModel.prediction is not thread-safe
        lock.lock()
        let output = try? model.prediction(from: inputFeatures)
        lock.unlock()

        guard let embeddingValue = output?.featureValue(for: "embedding"),
              let multiArray = embeddingValue.multiArrayValue,
              multiArray.count >= dimensions
        else { return nil }

        // Extract 384-dim vector using safe subscript access.
        // The output shape may be [384] or [1, 384] depending on the model;
        // MLMultiArray subscript with a flat index handles both.
        var vector = [Float](repeating: 0, count: dimensions)
        for i in 0..<dimensions {
            vector[i] = multiArray[i].floatValue
        }
        return vector
    }
}

// MARK: - NLEmbeddingProvider (Fallback)

final class NLEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {

    let dimensions: Int
    private let embedding: NLEmbedding

    init?() {
        guard let emb = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }
        self.embedding = emb
        self.dimensions = emb.dimension
    }

    func embed(_ text: String) -> [Float]? {
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }
}

// MARK: - Factory

enum EmbeddingProviderFactory {
    /// Returns the best available provider: CoreML if the model is bundled, otherwise NLEmbedding.
    static func makeProvider() -> (any EmbeddingProvider)? {
        if let coreML = CoreMLEmbeddingProvider() {
            return coreML
        }
        return NLEmbeddingProvider()
    }
}
