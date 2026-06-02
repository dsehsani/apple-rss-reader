//
//  ArticleTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ArticleTests: XCTestCase {

    // MARK: - Initialization

    func test_init_defaultValues() {
        let article = Article(title: "Hello", excerpt: "World", sourceID: UUID(), categoryID: UUID())

        XCTAssertFalse(article.isRead)
        XCTAssertFalse(article.isBookmarked)
        XCTAssertEqual(article.readTimeMinutes, 5)
        XCTAssertFalse(article.isPaywalled)
        XCTAssertFalse(article.isArchived)
        XCTAssertNil(article.clusterID)
        XCTAssertEqual(article.clusterSize, 1)
        XCTAssertTrue(article.isCanonical)
        XCTAssertNil(article.audioURL)
        XCTAssertNil(article.videoURL)
        XCTAssertEqual(article.articleURL, "https://example.com")
    }

    func test_init_customValues() {
        let clusterID = UUID()
        let article = TestFactory.makeArticle(
            isRead: true,
            isBookmarked: true,
            readTimeMinutes: 12,
            isPaywalled: true,
            isArchived: true,
            clusterID: clusterID,
            clusterSize: 5,
            isCanonical: false
        )

        XCTAssertTrue(article.isRead)
        XCTAssertTrue(article.isBookmarked)
        XCTAssertEqual(article.readTimeMinutes, 12)
        XCTAssertTrue(article.isPaywalled)
        XCTAssertTrue(article.isArchived)
        XCTAssertEqual(article.clusterID, clusterID)
        XCTAssertEqual(article.clusterSize, 5)
        XCTAssertFalse(article.isCanonical)
    }

    // MARK: - Codable

    func test_codable_roundTrip() throws {
        let original = TestFactory.makeArticle(
            title: "Coding Test",
            isBookmarked: true,
            audioURL: "https://example.com/audio.mp3"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Article.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.isBookmarked, original.isBookmarked)
        XCTAssertEqual(decoded.audioURL, original.audioURL)
    }

    func test_codable_backwardCompat_missingIsPaywalled() throws {
        // Simulate old JSON that lacks isPaywalled, isArchived, fetchedAt, etc.
        let id = UUID()
        let json: [String: Any] = [
            "id": id.uuidString,
            "title": "Old Article",
            "excerpt": "Old excerpt",
            "sourceID": UUID().uuidString,
            "categoryID": UUID().uuidString,
            "articleURL": "https://old.com",
            "publishedAt": Date().timeIntervalSinceReferenceDate,
            "isRead": false,
            "isBookmarked": true,
            "readTimeMinutes": 3
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        let article = try decoder.decode(Article.self, from: data)

        XCTAssertFalse(article.isPaywalled)
        XCTAssertFalse(article.isArchived)
        XCTAssertEqual(article.clusterSize, 1)
        XCTAssertTrue(article.isCanonical)
    }

    // MARK: - Date Validation

    func test_validatedPublishDate_validDate_returnsOriginal() {
        let candidate = Date().addingTimeInterval(-3600) // 1 hour ago
        let fetchedAt = Date()

        let result = Article.validatedPublishDate(candidate, fetchedAt: fetchedAt, feedName: "Test")
        XCTAssertEqual(result, candidate)
    }

    func test_validatedPublishDate_futureDateBeyondThreshold_returnsFetchedAt() {
        let farFuture = Date().addingTimeInterval(72 * 3600) // 72 hours from now
        let fetchedAt = Date()

        let result = Article.validatedPublishDate(farFuture, fetchedAt: fetchedAt, feedName: "Test")
        XCTAssertEqual(result, fetchedAt)
    }

    func test_validatedPublishDate_tooOld_returnsFetchedAt() {
        var components = DateComponents()
        components.year = 1990
        components.month = 1
        components.day = 1
        let ancient = Calendar.current.date(from: components)!
        let fetchedAt = Date()

        let result = Article.validatedPublishDate(ancient, fetchedAt: fetchedAt, feedName: "Test")
        XCTAssertEqual(result, fetchedAt)
    }

    func test_validatedPublishDate_futureWithinThreshold_returnsOriginal() {
        // 24 hours from now is within the 48-hour threshold
        let nearFuture = Date().addingTimeInterval(24 * 3600)
        let fetchedAt = Date()

        let result = Article.validatedPublishDate(nearFuture, fetchedAt: fetchedAt, feedName: "Test")
        XCTAssertEqual(result, nearFuture)
    }

    // MARK: - Decay Scoring

    func test_decayScore_brandNew_returnsOne() {
        let score = Article.decayScore(publishedAt: Date(), halfLifeHours: 48)
        XCTAssertEqual(score, 1.0, accuracy: 0.01)
    }

    func test_decayScore_atHalfLife_returnsHalf() {
        let halfLifeHours: Double = 48
        let publishedAt = Date().addingTimeInterval(-halfLifeHours * 3600)
        let score = Article.decayScore(publishedAt: publishedAt, halfLifeHours: halfLifeHours)
        XCTAssertEqual(score, 0.5, accuracy: 0.05)
    }

    func test_decayScore_veryOld_flooredAt02() {
        let publishedAt = Date().addingTimeInterval(-1000 * 3600) // ~41 days old
        let score = Article.decayScore(publishedAt: publishedAt, halfLifeHours: 48)
        XCTAssertEqual(score, 0.2)
    }

    func test_decayScore_futureDate_returnsOne() {
        // Future dates result in negative elapsed time, clamped to 0
        let futureDate = Date().addingTimeInterval(3600)
        let score = Article.decayScore(publishedAt: futureDate, halfLifeHours: 48)
        XCTAssertEqual(score, 1.0, accuracy: 0.01)
    }

    // MARK: - River Score

    func test_riverScore_noCluster_equalsDecayScore() {
        let decay = 0.8
        let score = Article.riverScore(decayScore: decay, clusterSize: 1, preferUniqueStories: false)
        XCTAssertEqual(score, decay, accuracy: 0.001)
    }

    func test_riverScore_withCluster_boosts() {
        let decay = 0.8
        let score = Article.riverScore(decayScore: decay, clusterSize: 5, preferUniqueStories: false)
        XCTAssertGreaterThan(score, decay)
    }

    func test_riverScore_withCluster_preferUnique_deboosted() {
        let decay = 0.8
        let score = Article.riverScore(decayScore: decay, clusterSize: 5, preferUniqueStories: true)
        XCTAssertLessThan(score, decay)
    }

    func test_riverScore_clusterSizeCapped() {
        let decay = 0.8
        let score10 = Article.riverScore(decayScore: decay, clusterSize: 10, preferUniqueStories: false)
        let score100 = Article.riverScore(decayScore: decay, clusterSize: 100, preferUniqueStories: false)
        // Both should be the same since cluster signal is capped at 10
        XCTAssertEqual(score10, score100, accuracy: 0.001)
    }

    // MARK: - Video Detection

    func test_isVideo_videoPath_returnsTrue() {
        let article = TestFactory.makeArticle(articleURL: "https://bbc.co.uk/news/videos/abc123")
        XCTAssertTrue(article.isVideo)
    }

    func test_isVideo_watchVideoPath_returnsTrue() {
        let article = TestFactory.makeArticle(articleURL: "https://skysports.com/watch/video/12345")
        XCTAssertTrue(article.isVideo)
    }

    func test_isVideo_normalPath_returnsFalse() {
        let article = TestFactory.makeArticle(articleURL: "https://example.com/news/story")
        XCTAssertFalse(article.isVideo)
    }

    func test_isVideo_invalidURL_returnsFalse() {
        let article = TestFactory.makeArticle(articleURL: "not a url")
        XCTAssertFalse(article.isVideo)
    }

    func test_isVideo_caseInsensitive() {
        let article = TestFactory.makeArticle(articleURL: "https://example.com/NEWS/VIDEOS/123")
        XCTAssertTrue(article.isVideo)
    }

    // MARK: - Relative Time String

    func test_relativeTimeString_returnsNonEmpty() {
        let article = TestFactory.makeArticle(publishedAt: Date().addingTimeInterval(-3600))
        XCTAssertFalse(article.relativeTimeString.isEmpty)
    }

    // MARK: - CachePolicy

    func test_cachePolicy_constants() {
        XCTAssertEqual(CachePolicy.cacheRetentionDays, 30)
        XCTAssertEqual(CachePolicy.displayWindowDays, 7)
        XCTAssertEqual(CachePolicy.maxFutureDateHours, 48)
        XCTAssertTrue(CachePolicy.minimumValidDate < Date())
    }

    // MARK: - Hashable

    func test_hashable_sameID_sameHash() {
        let id = UUID()
        let a1 = TestFactory.makeArticle(id: id, title: "A")
        let a2 = TestFactory.makeArticle(id: id, title: "B")
        XCTAssertEqual(a1.hashValue, a2.hashValue)
    }
}
