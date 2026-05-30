//
//  ArticleStateTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ArticleStateTests: XCTestCase {

    // MARK: - Hash

    func test_hash_deterministic() {
        let url = "https://example.com/article/123"
        let hash1 = ArticleState.hash(url)
        let hash2 = ArticleState.hash(url)
        XCTAssertEqual(hash1, hash2)
    }

    func test_hash_differentURLs_differentHashes() {
        let hash1 = ArticleState.hash("https://example.com/article/1")
        let hash2 = ArticleState.hash("https://example.com/article/2")
        XCTAssertNotEqual(hash1, hash2)
    }

    func test_hash_isSHA256_hexString() {
        let hash = ArticleState.hash("test")
        // SHA-256 produces 64 hex characters
        XCTAssertEqual(hash.count, 64)
        // Only hex chars
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { hexCharSet.contains($0) })
    }

    func test_hash_emptyString() {
        let hash = ArticleState.hash("")
        XCTAssertEqual(hash.count, 64)
        // SHA-256 of empty string is a known value
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func test_hash_caseSensitive() {
        let lower = ArticleState.hash("https://example.com")
        let upper = ArticleState.hash("https://EXAMPLE.com")
        XCTAssertNotEqual(lower, upper)
    }
}
