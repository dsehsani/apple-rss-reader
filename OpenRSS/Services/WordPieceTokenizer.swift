//
//  WordPieceTokenizer.swift
//  OpenRSS
//
//  WordPiece tokenizer for all-MiniLM-L6-v2.
//  Matches HuggingFace BertTokenizer behavior: lowercase, split on
//  whitespace + punctuation, greedy longest-match WordPiece.
//

import Foundation

struct WordPieceTokenizer: Sendable {

    // MARK: - Special Tokens

    static let padID: Int32 = 0
    static let unkID: Int32 = 100
    static let clsID: Int32 = 101
    static let sepID: Int32 = 102

    // MARK: - State

    private let vocab: [String: Int32]
    let maxLength: Int

    // MARK: - Init

    init(vocabURL: URL, maxLength: Int = 128) throws {
        let text = try String(contentsOf: vocabURL, encoding: .utf8)
        var dict: [String: Int32] = [:]
        dict.reserveCapacity(31_000)
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let token = String(line)
            if !token.isEmpty {
                dict[token] = Int32(index)
            }
        }
        self.vocab = dict
        self.maxLength = maxLength
    }

    // MARK: - Public API

    struct TokenizedInput: Sendable {
        let inputIDs: [Int32]
        let attentionMask: [Int32]
    }

    func tokenize(_ text: String) -> TokenizedInput {
        let lowered = text.lowercased()
        let pretokens = splitOnWhitespaceAndPunctuation(lowered)

        // WordPiece encode each pretoken
        var tokenIDs: [Int32] = [Self.clsID]
        let maxTokens = maxLength - 2 // reserve [CLS] and [SEP]

        for pretoken in pretokens {
            let subIDs = wordPieceEncode(pretoken)
            if tokenIDs.count - 1 + subIDs.count > maxTokens { break }
            tokenIDs.append(contentsOf: subIDs)
        }

        tokenIDs.append(Self.sepID)

        let realCount = tokenIDs.count
        let padCount = maxLength - realCount

        if padCount > 0 {
            tokenIDs.append(contentsOf: repeatElement(Self.padID, count: padCount))
        }

        var mask = [Int32](repeating: 1, count: realCount)
        if padCount > 0 {
            mask.append(contentsOf: repeatElement(Int32(0), count: padCount))
        }

        return TokenizedInput(inputIDs: tokenIDs, attentionMask: mask)
    }

    // MARK: - Pre-tokenization

    /// Splits text on whitespace and punctuation, keeping each punctuation
    /// character as its own token (matching BERT BasicTokenizer behavior).
    private func splitOnWhitespaceAndPunctuation(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for ch in text {
            if ch.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if isPunctuation(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Matches BERT's definition of punctuation: ASCII punctuation + Unicode Punctuation category.
    private func isPunctuation(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        // ASCII punctuation ranges (matches Python's _is_punctuation)
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64) ||
           (v >= 91 && v <= 96) || (v >= 123 && v <= 126) {
            return true
        }
        return ch.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
        }
    }

    // MARK: - WordPiece

    /// Greedy longest-match WordPiece encoding of a single pre-token.
    private func wordPieceEncode(_ token: String) -> [Int32] {
        if token.isEmpty { return [] }

        // Fast path: whole token in vocab
        if let id = vocab[token] { return [id] }

        var subTokenIDs: [Int32] = []
        var start = token.startIndex
        var isFirst = true

        while start < token.endIndex {
            var end = token.endIndex
            var matched = false

            while start < end {
                let substr = String(token[start..<end])
                let candidate = isFirst ? substr : "##" + substr
                if let id = vocab[candidate] {
                    subTokenIDs.append(id)
                    matched = true
                    start = end
                    break
                }
                end = token.index(before: end)
            }

            if !matched {
                subTokenIDs.append(Self.unkID)
                start = token.index(after: start)
            }
            isFirst = false
        }

        return subTokenIDs
    }
}
