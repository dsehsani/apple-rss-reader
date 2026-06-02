//
//  TodayViewModelTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class TodayViewModelTests: XCTestCase {

    private func makeVM(articles: [Article] = [], sources: [Source] = [], categories: [Category] = []) -> TodayViewModel {
        let mock = MockFeedDataService()
        mock.articles = articles
        mock.sources = sources
        mock.categories = categories
        return TodayViewModel(dataService: mock)
    }

    // MARK: - Initial State

    func test_init_defaultCategory_isAllUpdates() {
        let vm = makeVM()
        XCTAssertEqual(vm.selectedCategory?.id, Category.allUpdates.id)
    }

    func test_init_isRefreshing_false() {
        let vm = makeVM()
        XCTAssertFalse(vm.isRefreshing)
    }

    func test_init_hasActiveFilters_false() {
        let vm = makeVM()
        XCTAssertFalse(vm.hasActiveFilters)
    }

    // MARK: - allCategories

    func test_allCategories_includesAllUpdatesFirst() {
        let cats = [
            TestFactory.makeCategory(name: "Tech", sortOrder: 0),
            TestFactory.makeCategory(name: "Sports", sortOrder: 1),
        ]
        let vm = makeVM(categories: cats)
        XCTAssertEqual(vm.allCategories.first?.id, Category.allUpdates.id)
        XCTAssertEqual(vm.allCategories.count, 3) // All Updates + 2
    }

    func test_allCategories_sortedBySortOrder() {
        let cats = [
            TestFactory.makeCategory(id: UUID(), name: "B", sortOrder: 2),
            TestFactory.makeCategory(id: UUID(), name: "A", sortOrder: 1),
        ]
        let vm = makeVM(categories: cats)
        // Skip first (All Updates)
        XCTAssertEqual(vm.allCategories[1].name, "A")
        XCTAssertEqual(vm.allCategories[2].name, "B")
    }

    // MARK: - hasSources

    func test_hasSources_noSources_false() {
        let vm = makeVM()
        XCTAssertFalse(vm.hasSources)
    }

    func test_hasSources_withSources_true() {
        let vm = makeVM(sources: [TestFactory.makeSource()])
        XCTAssertTrue(vm.hasSources)
    }

    // MARK: - filteredArticles

    func test_filteredArticles_allUpdates_showsAll() {
        let catID = UUID()
        let articles = [
            TestFactory.makeArticle(categoryID: catID, publishedAt: Date()),
            TestFactory.makeArticle(categoryID: UUID(), publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        // Default is "All Updates"
        XCTAssertEqual(vm.filteredArticles.count, 2)
    }

    func test_filteredArticles_specificCategory_filtersCorrectly() {
        let catID = UUID()
        let otherCatID = UUID()
        let articles = [
            TestFactory.makeArticle(categoryID: catID, publishedAt: Date()),
            TestFactory.makeArticle(categoryID: catID, publishedAt: Date()),
            TestFactory.makeArticle(categoryID: otherCatID, publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        vm.selectedCategory = Category(id: catID, name: "Tech")
        XCTAssertEqual(vm.filteredArticles.count, 2)
    }

    func test_filteredArticles_olderThan7Days_filtered() {
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let articles = [
            TestFactory.makeArticle(publishedAt: Date()),
            TestFactory.makeArticle(publishedAt: oldDate),
        ]
        let vm = makeVM(articles: articles)
        XCTAssertEqual(vm.filteredArticles.count, 1)
    }

    func test_filteredArticles_sortedByDate() {
        let now = Date()
        let articles = [
            TestFactory.makeArticle(title: "Old", publishedAt: now.addingTimeInterval(-3600)),
            TestFactory.makeArticle(title: "New", publishedAt: now),
        ]
        let vm = makeVM(articles: articles)
        XCTAssertEqual(vm.filteredArticles.first?.title, "New")
    }

    // MARK: - Filter Options

    func test_filter_saved_showsOnlyBookmarked() {
        let articles = [
            TestFactory.makeArticle(isBookmarked: true, publishedAt: Date()),
            TestFactory.makeArticle(isBookmarked: false, publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        vm.activeFilters = [.saved]
        XCTAssertEqual(vm.filteredArticles.count, 1)
        XCTAssertTrue(vm.filteredArticles.first!.isBookmarked)
    }

    func test_filter_unread_showsOnlyUnread() {
        let articles = [
            TestFactory.makeArticle(isRead: false, publishedAt: Date()),
            TestFactory.makeArticle(isRead: true, publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        vm.activeFilters = [.unread]
        XCTAssertEqual(vm.filteredArticles.count, 1)
        XCTAssertFalse(vm.filteredArticles.first!.isRead)
    }

    func test_filter_today_showsOnlyToday() {
        let articles = [
            TestFactory.makeArticle(publishedAt: Date()),
            TestFactory.makeArticle(publishedAt: Date().addingTimeInterval(-86400 * 2)),
        ]
        let vm = makeVM(articles: articles)
        vm.activeFilters = [.today]
        XCTAssertEqual(vm.filteredArticles.count, 1)
    }

    func test_hasActiveFilters_toggling() {
        let vm = makeVM()
        XCTAssertFalse(vm.hasActiveFilters)
        vm.activeFilters = [.saved]
        XCTAssertTrue(vm.hasActiveFilters)
        vm.activeFilters = []
        XCTAssertFalse(vm.hasActiveFilters)
    }

    // MARK: - Search Integration

    func test_search_filtersArticles() {
        let articles = [
            TestFactory.makeArticle(title: "Swift Programming", publishedAt: Date()),
            TestFactory.makeArticle(title: "Python Guide", publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        vm.searchViewModel.searchText = "swift"
        XCTAssertEqual(vm.filteredArticles.count, 1)
    }

    // MARK: - Unread Count

    func test_unreadCount_allUpdates() {
        let articles = [
            TestFactory.makeArticle(isRead: false, publishedAt: Date()),
            TestFactory.makeArticle(isRead: false, publishedAt: Date()),
            TestFactory.makeArticle(isRead: true, publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        XCTAssertEqual(vm.unreadCount(for: Category.allUpdates), 2)
    }

    func test_unreadCount_specificCategory() {
        let catID = UUID()
        let articles = [
            TestFactory.makeArticle(categoryID: catID, isRead: false, publishedAt: Date()),
            TestFactory.makeArticle(categoryID: catID, isRead: true, publishedAt: Date()),
            TestFactory.makeArticle(categoryID: UUID(), isRead: false, publishedAt: Date()),
        ]
        let vm = makeVM(articles: articles)
        XCTAssertEqual(vm.unreadCount(for: Category(id: catID, name: "T")), 1)
    }

    // MARK: - Actions

    func test_selectCategory() {
        let vm = makeVM()
        let newCat = TestFactory.makeCategory(name: "Sports")
        vm.selectCategory(newCat)
        XCTAssertEqual(vm.selectedCategory?.id, newCat.id)
    }

    func test_source_forArticle() {
        let sourceID = UUID()
        let source = TestFactory.makeSource(id: sourceID, name: "TechCrunch")
        let article = TestFactory.makeArticle(sourceID: sourceID)
        let vm = makeVM(articles: [article], sources: [source])

        let found = vm.source(for: article)
        XCTAssertEqual(found?.name, "TechCrunch")
    }

    func test_category_forArticle() {
        let catID = UUID()
        let cat = TestFactory.makeCategory(id: catID, name: "Tech")
        let article = TestFactory.makeArticle(categoryID: catID)
        let vm = makeVM(articles: [article], categories: [cat])

        let found = vm.category(for: article)
        XCTAssertEqual(found?.name, "Tech")
    }
}
