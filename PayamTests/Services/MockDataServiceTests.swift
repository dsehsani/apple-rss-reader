//
//  MockDataServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class MockDataServiceTests: XCTestCase {

    // MARK: - MockFeedDataService (from TestHelpers)

    func test_source_found() {
        let mock = MockFeedDataService()
        let source = TestFactory.makeSource()
        mock.sources = [source]

        XCTAssertNotNil(mock.source(for: source.id))
        XCTAssertEqual(mock.source(for: source.id)?.name, "Test Source")
    }

    func test_source_notFound() {
        let mock = MockFeedDataService()
        XCTAssertNil(mock.source(for: UUID()))
    }

    func test_category_found() {
        let mock = MockFeedDataService()
        let cat = TestFactory.makeCategory()
        mock.categories = [cat]

        XCTAssertNotNil(mock.category(for: cat.id))
    }

    func test_category_notFound() {
        let mock = MockFeedDataService()
        XCTAssertNil(mock.category(for: UUID()))
    }

    func test_articlesForCategory() {
        let mock = MockFeedDataService()
        let catID = UUID()
        let otherCatID = UUID()
        mock.articles = [
            TestFactory.makeArticle(categoryID: catID),
            TestFactory.makeArticle(categoryID: catID),
            TestFactory.makeArticle(categoryID: otherCatID),
        ]

        XCTAssertEqual(mock.articlesForCategory(catID).count, 2)
        XCTAssertEqual(mock.articlesForCategory(otherCatID).count, 1)
    }

    func test_articlesForSource() {
        let mock = MockFeedDataService()
        let srcID = UUID()
        mock.articles = [
            TestFactory.makeArticle(sourceID: srcID),
            TestFactory.makeArticle(sourceID: UUID()),
        ]

        XCTAssertEqual(mock.articlesForSource(srcID).count, 1)
    }

    func test_unreadCountForCategory() {
        let mock = MockFeedDataService()
        let catID = UUID()
        mock.articles = [
            TestFactory.makeArticle(categoryID: catID, isRead: false),
            TestFactory.makeArticle(categoryID: catID, isRead: true),
            TestFactory.makeArticle(categoryID: catID, isRead: false),
        ]

        XCTAssertEqual(mock.unreadCountForCategory(catID), 2)
    }

    func test_unreadCountForSource() {
        let mock = MockFeedDataService()
        let srcID = UUID()
        mock.articles = [
            TestFactory.makeArticle(sourceID: srcID, isRead: false),
            TestFactory.makeArticle(sourceID: srcID, isRead: false),
            TestFactory.makeArticle(sourceID: srcID, isRead: true),
        ]

        XCTAssertEqual(mock.unreadCountForSource(srcID), 2)
    }

    func test_toggleBookmark() {
        let mock = MockFeedDataService()
        let article = TestFactory.makeArticle(isBookmarked: false)
        mock.articles = [article]

        mock.toggleBookmark(for: article.id)
        XCTAssertTrue(mock.articles[0].isBookmarked)

        mock.toggleBookmark(for: article.id)
        XCTAssertFalse(mock.articles[0].isBookmarked)
    }

    func test_markAsRead() {
        let mock = MockFeedDataService()
        let article = TestFactory.makeArticle(isRead: false)
        mock.articles = [article]

        mock.markAsRead(article.id)
        XCTAssertTrue(mock.articles[0].isRead)
    }

    func test_markAsUnread() {
        let mock = MockFeedDataService()
        let article = TestFactory.makeArticle(isRead: true)
        mock.articles = [article]

        mock.markAsUnread(article.id)
        XCTAssertFalse(mock.articles[0].isRead)
    }

    func test_splitCluster() {
        let mock = MockFeedDataService()
        let clusterID = UUID()
        let a1 = TestFactory.makeArticle(clusterID: clusterID, clusterSize: 3)
        let a2 = TestFactory.makeArticle(clusterID: clusterID, clusterSize: 3)
        let a3 = TestFactory.makeArticle(clusterID: nil, clusterSize: 1)
        mock.articles = [a1, a2, a3]

        mock.splitCluster(for: a1.id)

        XCTAssertNil(mock.articles[0].clusterID)
        XCTAssertEqual(mock.articles[0].clusterSize, 1)
        XCTAssertTrue(mock.articles[0].isCanonical)

        XCTAssertNil(mock.articles[1].clusterID)
        XCTAssertEqual(mock.articles[1].clusterSize, 1)

        // Non-clustered article should be unchanged
        XCTAssertNil(mock.articles[2].clusterID)
    }

    func test_splitCluster_noCluster_noOp() {
        let mock = MockFeedDataService()
        let article = TestFactory.makeArticle(clusterID: nil)
        mock.articles = [article]

        mock.splitCluster(for: article.id)
        XCTAssertNil(mock.articles[0].clusterID)
    }
}
