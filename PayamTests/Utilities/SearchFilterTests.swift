//
//  SearchFilterTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class SearchFilterTests: XCTestCase {

    // MARK: - fuzzyMatch

    func test_fuzzyMatch_substring_matches() {
        XCTAssertTrue(fuzzyMatch("hello world", query: "world"))
    }

    func test_fuzzyMatch_subsequence_matches() {
        XCTAssertTrue(fuzzyMatch("hello world", query: "hlo"))
    }

    func test_fuzzyMatch_noMatch() {
        XCTAssertFalse(fuzzyMatch("hello world", query: "xyz"))
    }

    func test_fuzzyMatch_emptyQuery_matches() {
        XCTAssertTrue(fuzzyMatch("anything", query: ""))
    }

    func test_fuzzyMatch_emptyTarget_doesNotMatch() {
        XCTAssertFalse(fuzzyMatch("", query: "abc"))
    }

    func test_fuzzyMatch_exactMatch() {
        XCTAssertTrue(fuzzyMatch("hello", query: "hello"))
    }

    func test_fuzzyMatch_fragmentedInput() {
        // "rss fd" → "RSS Feed" via subsequence
        XCTAssertTrue(fuzzyMatch("rss feed", query: "rss fd"))
    }

    // MARK: - TitleOnlyFilter

    func test_titleOnlyFilter_matchesTitle() {
        let filter = TitleOnlyFilter()
        let article = TestFactory.makeArticle(title: "Swift Programming Guide")
        XCTAssertTrue(filter.matches(article: article, query: "swift"))
    }

    func test_titleOnlyFilter_doesNotMatchExcerpt() {
        let filter = TitleOnlyFilter()
        let article = TestFactory.makeArticle(title: "Generic Title", excerpt: "This talks about Swift.")
        XCTAssertFalse(filter.matches(article: article, query: "swift"))
    }

    func test_titleOnlyFilter_caseInsensitive() {
        let filter = TitleOnlyFilter()
        let article = TestFactory.makeArticle(title: "HELLO WORLD")
        XCTAssertTrue(filter.matches(article: article, query: "hello"))
    }

    // MARK: - TitleAndContentFilter

    func test_titleAndContentFilter_matchesTitle() {
        let filter = TitleAndContentFilter()
        let article = TestFactory.makeArticle(title: "Swift Guide", excerpt: "Not about Swift")
        XCTAssertTrue(filter.matches(article: article, query: "swift"))
    }

    func test_titleAndContentFilter_matchesExcerpt() {
        let filter = TitleAndContentFilter()
        let article = TestFactory.makeArticle(title: "Generic", excerpt: "This is about Rust programming")
        XCTAssertTrue(filter.matches(article: article, query: "rust"))
    }

    func test_titleAndContentFilter_noMatch() {
        let filter = TitleAndContentFilter()
        let article = TestFactory.makeArticle(title: "Hello", excerpt: "World")
        XCTAssertFalse(filter.matches(article: article, query: "python"))
    }

    // MARK: - SearchMode

    func test_searchMode_titleOnly_createsTitleFilter() {
        let filter = SearchMode.titleOnly.makeFilter()
        XCTAssertTrue(filter is TitleOnlyFilter)
    }

    func test_searchMode_titleAndContent_createsTitleAndContentFilter() {
        let filter = SearchMode.titleAndContent.makeFilter()
        XCTAssertTrue(filter is TitleAndContentFilter)
    }
}
