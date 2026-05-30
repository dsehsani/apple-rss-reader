//
//  RSSCatalogTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class RSSCatalogTests: XCTestCase {

    // MARK: - Featured Feeds

    func test_featuredFeeds_nonEmpty() {
        XCTAssertFalse(RSSCatalog.featuredFeeds.isEmpty)
    }

    func test_featuredFeeds_allHaveValidURLs() {
        for feed in RSSCatalog.featuredFeeds {
            XCTAssertNotNil(URL(string: feed.feedURL), "Invalid URL: \(feed.feedURL)")
        }
    }

    func test_featuredGradients_matchFeaturedCount() {
        XCTAssertEqual(RSSCatalog.featuredGradients.count, RSSCatalog.featuredFeeds.count)
    }

    // MARK: - Categories

    func test_categories_nonEmpty() {
        XCTAssertFalse(RSSCatalog.categories.isEmpty)
    }

    func test_categories_allHaveFeeds() {
        for cat in RSSCatalog.categories {
            XCTAssertFalse(cat.feeds.isEmpty, "Category '\(cat.name)' has no feeds")
        }
    }

    func test_categories_uniqueNames() {
        let names = RSSCatalog.categories.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Duplicate category names found")
    }

    // MARK: - CatalogFeed

    func test_catalogFeed_id_isFeedURL() {
        let feed = CatalogFeed(name: "Test", feedURL: "https://test.com/feed", description: "Desc")
        XCTAssertEqual(feed.id, "https://test.com/feed")
    }

    func test_catalogFeed_websiteURL_derivedFromFeedURL() {
        let feed = CatalogFeed(
            name: "Test",
            feedURL: "https://example.com/rss/index.xml",
            description: "Desc"
        )
        XCTAssertEqual(feed.websiteURL, "https://example.com")
    }

    func test_catalogFeed_equatable_caseInsensitive() {
        let a = CatalogFeed(name: "A", feedURL: "https://Example.com/FEED", description: "")
        let b = CatalogFeed(name: "B", feedURL: "https://example.com/feed", description: "")
        XCTAssertEqual(a, b)
    }

    func test_catalogFeed_hashable_caseInsensitive() {
        let a = CatalogFeed(name: "A", feedURL: "https://Example.com/FEED", description: "")
        let b = CatalogFeed(name: "B", feedURL: "https://example.com/feed", description: "")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - Recommended Feeds

    func test_recommendedFeeds_excludesSubscribed() {
        let subscribed: Set<String> = ["https://news.ycombinator.com/rss"]
        let recs = RSSCatalog.recommendedFeeds(subscribedURLs: subscribed, limit: 100)
        XCTAssertFalse(recs.contains(where: { $0.feedURL.lowercased() == "https://news.ycombinator.com/rss" }))
    }

    func test_recommendedFeeds_respectsLimit() {
        let recs = RSSCatalog.recommendedFeeds(subscribedURLs: [], limit: 3)
        XCTAssertLessThanOrEqual(recs.count, 3)
    }

    func test_recommendedFeeds_noDuplicates() {
        let recs = RSSCatalog.recommendedFeeds(subscribedURLs: [], limit: 50)
        let urls = recs.map { $0.feedURL.lowercased() }
        XCTAssertEqual(urls.count, Set(urls).count, "Recommendations contain duplicates")
    }

    func test_recommendedFeeds_emptySubscriptions_returnsDefaultLimit() {
        let recs = RSSCatalog.recommendedFeeds(subscribedURLs: [])
        XCTAssertLessThanOrEqual(recs.count, 8)
    }

    // MARK: - Category Lookup

    func test_categoryForFeed_found() {
        let feed = RSSCatalog.techCategory.feeds.first!
        let cat = RSSCatalog.category(for: feed)
        XCTAssertNotNil(cat)
        XCTAssertEqual(cat?.name, "Tech")
    }

    func test_categoryForFeed_notFound() {
        let unknown = CatalogFeed(name: "Unknown", feedURL: "https://nocat.com/feed", description: "")
        XCTAssertNil(RSSCatalog.category(for: unknown))
    }
}
