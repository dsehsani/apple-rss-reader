//
//  WordPieceTokenizerTests.swift
//  OpenRSSTests
//
//  Validates WordPieceTokenizer output matches HuggingFace BertTokenizer
//  reference values (sentence-transformers/all-MiniLM-L6-v2).
//

import Testing
import Foundation
@testable import OpenRSS

@Suite("WordPiece Tokenizer")
struct WordPieceTokenizerTests {

    let tokenizer: WordPieceTokenizer

    init() throws {
        // Tests are hosted in the app, so Bundle.main is the app bundle
        // where vocab.txt lives under Resources/ML/.
        let vocabURL =
            Bundle.main.url(forResource: "vocab", withExtension: "txt", subdirectory: "Resources/ML")
            ?? Bundle.main.url(forResource: "vocab", withExtension: "txt")!
        tokenizer = try WordPieceTokenizer(vocabURL: vocabURL, maxLength: 16)
    }

    // MARK: - Basic Tokenization

    @Test("Simple sentence matches Python reference IDs")
    func simpleSentence() {
        // Python: tokenizer("Apple announces new iPhone", max_length=16, padding="max_length")
        // → [101, 6207, 17472, 2047, 18059, 102, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let result = tokenizer.tokenize("Apple announces new iPhone")
        #expect(result.inputIDs == [101, 6207, 17472, 2047, 18059, 102, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(result.attentionMask == [1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: - Subword Splitting

    @Test("Subword splitting matches Python reference")
    func subwordSplitting() {
        // Python: tokenizer("embeddings", max_length=16)
        // → ['[CLS]', 'em', '##bed', '##ding', '##s', '[SEP]', ...]
        // → [101, 7861, 8270, 4667, 2015, 102, 0, ...]
        let result = tokenizer.tokenize("embeddings")
        let realTokens = Array(result.inputIDs.prefix(6))
        #expect(realTokens == [101, 7861, 8270, 4667, 2015, 102])
    }

    // MARK: - Punctuation Handling

    @Test("Punctuation split as separate tokens")
    func punctuation() {
        // Python: tokenizer("it's a test-case, isn't it?", max_length=16)
        // → [101, 2009, 1005, 1055, 1037, 3231, 1011, 2553, 1010, 3475, 1005, 1056, 2009, 1029, 102, 0]
        let result = tokenizer.tokenize("it's a test-case, isn't it?")
        #expect(result.inputIDs == [101, 2009, 1005, 1055, 1037, 3231, 1011, 2553, 1010, 3475, 1005, 1056, 2009, 1029, 102, 0])
    }

    // MARK: - Special Cases

    @Test("Empty string produces [CLS] [SEP] + padding")
    func emptyString() {
        let result = tokenizer.tokenize("")
        #expect(result.inputIDs[0] == WordPieceTokenizer.clsID)
        #expect(result.inputIDs[1] == WordPieceTokenizer.sepID)
        #expect(result.inputIDs.count == 16)
        #expect(result.attentionMask[0] == 1)
        #expect(result.attentionMask[1] == 1)
        #expect(result.attentionMask[2] == 0)
    }

    @Test("Output length always equals maxLength")
    func fixedLength() {
        let short = tokenizer.tokenize("hi")
        #expect(short.inputIDs.count == 16)
        #expect(short.attentionMask.count == 16)

        let long = tokenizer.tokenize("This is a much longer sentence that should be truncated to fit within the maximum sequence length limit")
        #expect(long.inputIDs.count == 16)
        #expect(long.attentionMask.count == 16)
        // Should end with [SEP]
        let lastReal = long.attentionMask.lastIndex(of: 1)!
        #expect(long.inputIDs[lastReal] == WordPieceTokenizer.sepID)
    }

    @Test("Case insensitive")
    func caseInsensitive() {
        let upper = tokenizer.tokenize("APPLE")
        let lower = tokenizer.tokenize("apple")
        #expect(upper.inputIDs == lower.inputIDs)
    }
}
