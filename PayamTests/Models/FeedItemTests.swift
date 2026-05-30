//
//  FeedItemTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class FeedItemTests: XCTestCase {

    // MARK: - Initialization

    func test_init_defaultValues() {
        let item = TestFactory.makeFeedItem()

        XCTAssertFalse(item.agedOut)
        XCTAssertTrue(item.riverVisible)
        XCTAssertEqual(item.relevanceScore, 1.0)
        XCTAssertEqual(item.velocityTier, .article)
        XCTAssertFalse(item.isCanonical)
        XCTAssertNil(item.clusterID)
        XCTAssertEqual(item.simhashValue, 0)
        XCTAssertNil(item.embeddingVector)
    }

    // MARK: - Equatable

    func test_equatable_sameID_sameFields_equal() {
        let id = UUID()
        let a = TestFactory.makeFeedItem(id: id, title: "A")
        let b = TestFactory.makeFeedItem(id: id, title: "A")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentID_notEqual() {
        let a = TestFactory.makeFeedItem(title: "Same Title")
        let b = TestFactory.makeFeedItem(title: "Same Title")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Hashable

    func test_hashable_usesID() {
        let id = UUID()
        let a = TestFactory.makeFeedItem(id: id, title: "A")
        let b = TestFactory.makeFeedItem(id: id, title: "B")
        // Hash only uses id
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - toArticle Conversion

    func test_toArticle_mapsFieldsCorrectly() {
        let catID = UUID()
        let item = TestFactory.makeFeedItem(
            title: "Converted Title",
            link: URL(string: "https://example.com/page")!,
            excerpt: "Some excerpt text",
            imageURL: "https://example.com/hero.jpg"
        )

        let article = item.toArticle(categoryID: catID)

        XCTAssertEqual(article.id, item.id)
        XCTAssertEqual(article.title, "Converted Title")
        XCTAssertEqual(article.excerpt, "Some excerpt text")
        XCTAssertEqual(article.sourceID, item.sourceID)
        XCTAssertEqual(article.categoryID, catID)
        XCTAssertEqual(article.articleURL, "https://example.com/page")
        XCTAssertEqual(article.imageURL, "https://example.com/hero.jpg")
        XCTAssertFalse(article.isRead)
        XCTAssertFalse(article.isBookmarked)
        XCTAssertFalse(article.isPaywalled)
    }

    func test_toArticle_clusterSize_passedThrough() {
        let item = TestFactory.makeFeedItem(clusterID: UUID(), isCanonical: true)
        let article = item.toArticle(categoryID: UUID(), clusterSize: 7)
        XCTAssertEqual(article.clusterSize, 7)
        XCTAssertTrue(article.isCanonical)
    }

    func test_toArticle_nilClusterID_alwaysCanonical() {
        let item = TestFactory.makeFeedItem(clusterID: nil, isCanonical: false)
        let article = item.toArticle(categoryID: UUID())
        XCTAssertTrue(article.isCanonical)
    }

    func test_toArticle_vimeoLink_nilsImageURL() {
        let item = TestFactory.makeFeedItem(
            link: URL(string: "https://vimeo.com/12345")!,
            imageURL: "https://vimeo.com/stale-brand-image.jpg"
        )
        let article = item.toArticle(categoryID: UUID())
        XCTAssertNil(article.imageURL, "Vimeo watch URLs should have nil imageURL to trigger OG resolution")
    }

    func test_toArticle_vimeoBlogLink_keepsImageURL() {
        let item = TestFactory.makeFeedItem(
            link: URL(string: "https://vimeo.com/blog/post/annual-recap")!,
            imageURL: "https://vimeo.com/blog-image.jpg"
        )
        let article = item.toArticle(categoryID: UUID())
        XCTAssertEqual(article.imageURL, "https://vimeo.com/blog-image.jpg")
    }

    // MARK: - Estimated Read Time

    func test_toArticle_readTimeEstimate_shortExcerpt() {
        let item = TestFactory.makeFeedItem(excerpt: "Short")
        let article = item.toArticle(categoryID: UUID())
        XCTAssertEqual(article.readTimeMinutes, 1, "Very short excerpts should clamp to 1 minute")
    }

    func test_toArticle_readTimeEstimate_longExcerpt() {
        let words = Array(repeating: "word", count: 6000).joined(separator: " ")
        let item = TestFactory.makeFeedItem(excerpt: words)
        let article = item.toArticle(categoryID: UUID())
        XCTAssertEqual(article.readTimeMinutes, 30, "Read time should be capped at 30 minutes")
    }
}
