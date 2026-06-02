//
//  FilterRuleServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class FilterRuleServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeRule(
        keywords: [String] = [],
        phrases: [String] = [],
        sourceFeedURLs: [String] = [],
        contentKinds: [String] = [],
        scope: FilterScope = .global
    ) -> FilterRuleSnapshot {
        FilterRuleSnapshot(
            id: UUID(),
            displayText: "Test Rule",
            predicate: FilterPredicate(
                keywords: keywords,
                phrases: phrases,
                sourceFeedURLs: sourceFeedURLs,
                contentKinds: contentKinds
            ),
            scope: scope
        )
    }

    // MARK: - Keyword Matching

    func test_matchingRule_keyword_wholeWord_matches() {
        let rule = makeRule(keywords: ["bitcoin"])
        let item = TestFactory.makeFeedItem(title: "Bitcoin price surges today")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_keyword_substring_doesNotMatch() {
        let rule = makeRule(keywords: ["coin"])
        // "coin" should match as a whole word inside "Bitcoin" would fail whole-word check
        let item = TestFactory.makeFeedItem(title: "Bitcoin surges", excerpt: "")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        // "coin" is not a whole word in "Bitcoin"
        XCTAssertNil(match)
    }

    func test_matchingRule_keyword_inExcerpt_matches() {
        let rule = makeRule(keywords: ["crypto"])
        let item = TestFactory.makeFeedItem(title: "Market Update", excerpt: "Crypto assets rise sharply")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    // MARK: - Phrase Matching

    func test_matchingRule_phrase_matches() {
        let rule = makeRule(phrases: ["breaking news"])
        let item = TestFactory.makeFeedItem(title: "Breaking News: Storm hits coast")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_phrase_caseInsensitive() {
        let rule = makeRule(phrases: ["BREAKING NEWS"])
        let item = TestFactory.makeFeedItem(title: "breaking news alert")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    // MARK: - Source Feed URL Matching

    func test_matchingRule_sourceFeedURL_matches() {
        let feedURL = "https://example.com/feed"
        let rule = makeRule(sourceFeedURLs: [feedURL])
        let item = TestFactory.makeFeedItem()
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: feedURL, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_sourceFeedURL_caseInsensitive() {
        let rule = makeRule(sourceFeedURLs: ["HTTPS://EXAMPLE.COM/FEED"])
        let item = TestFactory.makeFeedItem()
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: "https://example.com/feed", sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    // MARK: - Content Kind Matching

    func test_matchingRule_contentKind_podcast_withAudioURL() {
        let rule = makeRule(contentKinds: ["podcast"])
        let item = TestFactory.makeFeedItem(audioURL: "https://example.com/episode.mp3")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_contentKind_video_withVideoURL() {
        let rule = makeRule(contentKinds: ["video"])
        let item = TestFactory.makeFeedItem(videoURL: "https://youtube.com/watch?v=abc")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_contentKind_opinion_inTitle() {
        let rule = makeRule(contentKinds: ["opinion"])
        let item = TestFactory.makeFeedItem(title: "Opinion: Why tech needs regulation")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    // MARK: - Scope

    func test_matchingRule_globalScope_alwaysApplies() {
        let rule = makeRule(keywords: ["test"], scope: .global)
        let item = TestFactory.makeFeedItem(title: "Test article")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: "any", sourceFolderName: "any", rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_folderScope_matchingFolder_applies() {
        let rule = makeRule(keywords: ["test"], scope: .folder(name: "Tech"))
        let item = TestFactory.makeFeedItem(title: "Test article")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: "Tech", rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_folderScope_differentFolder_doesNotApply() {
        let rule = makeRule(keywords: ["test"], scope: .folder(name: "Tech"))
        let item = TestFactory.makeFeedItem(title: "Test article")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: "Sports", rules: [rule]
        )
        XCTAssertNil(match)
    }

    func test_matchingRule_feedScope_matchingFeed_applies() {
        let feedURL = "https://example.com/feed"
        let rule = makeRule(keywords: ["test"], scope: .feed(url: feedURL))
        let item = TestFactory.makeFeedItem(title: "Test article")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: feedURL, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNotNil(match)
    }

    func test_matchingRule_feedScope_differentFeed_doesNotApply() {
        let rule = makeRule(keywords: ["test"], scope: .feed(url: "https://other.com/feed"))
        let item = TestFactory.makeFeedItem(title: "Test article")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: "https://example.com/feed", sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNil(match)
    }

    // MARK: - Empty Predicate

    func test_matchingRule_emptyPredicate_doesNotMatch() {
        let rule = makeRule() // all empty
        let item = TestFactory.makeFeedItem(title: "Anything")
        let match = FilterRuleService.matchingRule(
            for: item, sourceFeedURL: nil, sourceFolderName: nil, rules: [rule]
        )
        XCTAssertNil(match)
    }

    // MARK: - filter() Batch

    func test_filter_noRules_returnsAll() {
        let items = (0..<5).map { _ in TestFactory.makeFeedItem() }
        let result = FilterRuleService.filter(items: items, sourceMap: [:], rules: [])
        XCTAssertEqual(result.count, 5)
    }

    func test_filter_withMatchingRule_removesMatches() {
        let rule = makeRule(keywords: ["bitcoin"])
        let items = [
            TestFactory.makeFeedItem(title: "Bitcoin surges"),
            TestFactory.makeFeedItem(title: "Apple announces new Mac"),
            TestFactory.makeFeedItem(title: "Bitcoin drops again"),
        ]
        let result = FilterRuleService.filter(items: items, sourceMap: [:], rules: [rule])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Apple announces new Mac")
    }
}
