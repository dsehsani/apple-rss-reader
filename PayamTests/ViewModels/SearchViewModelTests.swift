//
//  SearchViewModelTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class SearchViewModelTests: XCTestCase {

    // MARK: - Initial State

    func test_init_defaultMode_titleOnly() {
        let vm = SearchViewModel()
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertFalse(vm.hasActiveQuery)
    }

    func test_init_customMode() {
        let vm = SearchViewModel(mode: .titleAndContent)
        XCTAssertTrue(vm.searchText.isEmpty)
    }

    // MARK: - hasActiveQuery

    func test_hasActiveQuery_empty_false() {
        let vm = SearchViewModel()
        vm.searchText = ""
        XCTAssertFalse(vm.hasActiveQuery)
    }

    func test_hasActiveQuery_whitespace_false() {
        let vm = SearchViewModel()
        vm.searchText = "   "
        XCTAssertFalse(vm.hasActiveQuery)
    }

    func test_hasActiveQuery_withText_true() {
        let vm = SearchViewModel()
        vm.searchText = "swift"
        XCTAssertTrue(vm.hasActiveQuery)
    }

    // MARK: - clear

    func test_clear_resetsSearchText() {
        let vm = SearchViewModel()
        vm.searchText = "some query"
        vm.clear()
        XCTAssertTrue(vm.searchText.isEmpty)
    }

    // MARK: - filteredArticles

    func test_filteredArticles_emptyQuery_returnsAll() {
        let vm = SearchViewModel()
        let articles = [
            TestFactory.makeArticle(title: "A"),
            TestFactory.makeArticle(title: "B"),
        ]
        let result = vm.filteredArticles(from: articles)
        XCTAssertEqual(result.count, 2)
    }

    func test_filteredArticles_withQuery_filters() {
        let vm = SearchViewModel()
        vm.searchText = "swift"
        let articles = [
            TestFactory.makeArticle(title: "Swift Programming"),
            TestFactory.makeArticle(title: "Python Guide"),
            TestFactory.makeArticle(title: "Learning SwiftUI"),
        ]
        let result = vm.filteredArticles(from: articles)
        XCTAssertEqual(result.count, 2)
    }

    func test_filteredArticles_caseInsensitive() {
        let vm = SearchViewModel()
        vm.searchText = "SWIFT"
        let articles = [TestFactory.makeArticle(title: "swift programming")]
        let result = vm.filteredArticles(from: articles)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - matches

    func test_matches_emptyQuery_allMatch() {
        let vm = SearchViewModel()
        let article = TestFactory.makeArticle(title: "Anything")
        XCTAssertTrue(vm.matches(article))
    }

    func test_matches_withQuery_matchingTitle() {
        let vm = SearchViewModel()
        vm.searchText = "tech"
        let article = TestFactory.makeArticle(title: "TechCrunch Article")
        XCTAssertTrue(vm.matches(article))
    }

    func test_matches_withQuery_noMatch() {
        let vm = SearchViewModel()
        vm.searchText = "python"
        let article = TestFactory.makeArticle(title: "Swift Guide")
        XCTAssertFalse(vm.matches(article))
    }

    // MARK: - Mode Switching

    func test_modeSwitch_changesFilterBehavior() {
        let vm = SearchViewModel(mode: .titleOnly)
        vm.searchText = "content keyword"

        let article = TestFactory.makeArticle(
            title: "Generic Title",
            excerpt: "This has the content keyword here."
        )

        // Title only: shouldn't find "content keyword" in title
        XCTAssertFalse(vm.matches(article))

        // Switch to title+content
        vm.mode = .titleAndContent
        XCTAssertTrue(vm.matches(article))
    }
}
