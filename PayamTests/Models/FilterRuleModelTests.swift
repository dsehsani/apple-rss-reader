//
//  FilterRuleModelTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class FilterRuleModelTests: XCTestCase {

    // MARK: - FilterPredicate

    func test_filterPredicate_empty() {
        let p = FilterPredicate.empty
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.keywords.isEmpty)
        XCTAssertTrue(p.phrases.isEmpty)
        XCTAssertTrue(p.sourceFeedURLs.isEmpty)
        XCTAssertTrue(p.contentKinds.isEmpty)
    }

    func test_filterPredicate_nonEmpty() {
        let p = FilterPredicate(keywords: ["AI"], phrases: [], sourceFeedURLs: [], contentKinds: [])
        XCTAssertFalse(p.isEmpty)
    }

    func test_filterPredicate_codable() throws {
        let original = FilterPredicate(
            keywords: ["tech", "ai"],
            phrases: ["breaking news"],
            sourceFeedURLs: ["https://example.com/feed"],
            contentKinds: ["opinion"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FilterPredicate.self, from: data)

        XCTAssertEqual(decoded.keywords, original.keywords)
        XCTAssertEqual(decoded.phrases, original.phrases)
        XCTAssertEqual(decoded.sourceFeedURLs, original.sourceFeedURLs)
        XCTAssertEqual(decoded.contentKinds, original.contentKinds)
    }

    // MARK: - FilterScope

    func test_filterScope_global_rawValue() {
        let scope = FilterScope.global
        XCTAssertEqual(scope.raw, "global")
    }

    func test_filterScope_folder_rawValue() {
        let scope = FilterScope.folder(name: "Tech")
        XCTAssertEqual(scope.raw, "folder:Tech")
    }

    func test_filterScope_feed_rawValue() {
        let scope = FilterScope.feed(url: "https://example.com/feed")
        XCTAssertEqual(scope.raw, "feed:https://example.com/feed")
    }

    func test_filterScope_initFromRaw_global() {
        let scope = FilterScope(raw: "global")
        XCTAssertEqual(scope, .global)
    }

    func test_filterScope_initFromRaw_folder() {
        let scope = FilterScope(raw: "folder:Design")
        XCTAssertEqual(scope, .folder(name: "Design"))
    }

    func test_filterScope_initFromRaw_feed() {
        let scope = FilterScope(raw: "feed:https://test.com/rss")
        XCTAssertEqual(scope, .feed(url: "https://test.com/rss"))
    }

    func test_filterScope_initFromRaw_unknown_defaultsToGlobal() {
        let scope = FilterScope(raw: "something_random")
        XCTAssertEqual(scope, .global)
    }

    // MARK: - FilterRuleSnapshot

    func test_filterRuleSnapshot_equatable() {
        let id = UUID()
        let pred = FilterPredicate(keywords: ["AI"], phrases: [], sourceFeedURLs: [], contentKinds: [])
        let a = FilterRuleSnapshot(id: id, displayText: "Test", predicate: pred, scope: .global)
        let b = FilterRuleSnapshot(id: id, displayText: "Test", predicate: pred, scope: .global)
        XCTAssertEqual(a.id, b.id)
    }
}
