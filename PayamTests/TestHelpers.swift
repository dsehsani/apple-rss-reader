//
//  TestHelpers.swift
//  PayamTests
//
//  Shared test utilities: mock data factories, helpers, and stubs.
//

import Foundation
@testable import Payam

// MARK: - Article Factory

enum TestFactory {

    // MARK: - Fixed UUIDs

    static let sourceID   = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let categoryID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let articleID  = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    static let folderID   = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

    // MARK: - Article

    static func makeArticle(
        id: UUID = UUID(),
        title: String = "Test Article",
        excerpt: String = "This is a test excerpt for unit testing purposes.",
        sourceID: UUID = TestFactory.sourceID,
        categoryID: UUID = TestFactory.categoryID,
        imageURL: String? = "https://example.com/image.jpg",
        audioURL: String? = nil,
        videoURL: String? = nil,
        articleURL: String = "https://example.com/article",
        publishedAt: Date = Date(),
        fetchedAt: Date = Date(),
        isRead: Bool = false,
        isBookmarked: Bool = false,
        readTimeMinutes: Int = 5,
        isPaywalled: Bool = false,
        isArchived: Bool = false,
        clusterID: UUID? = nil,
        clusterSize: Int = 1,
        isCanonical: Bool = true
    ) -> Article {
        Article(
            id: id,
            title: title,
            excerpt: excerpt,
            sourceID: sourceID,
            categoryID: categoryID,
            imageURL: imageURL,
            audioURL: audioURL,
            videoURL: videoURL,
            articleURL: articleURL,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            isRead: isRead,
            isBookmarked: isBookmarked,
            readTimeMinutes: readTimeMinutes,
            isPaywalled: isPaywalled,
            isArchived: isArchived,
            clusterID: clusterID,
            clusterSize: clusterSize,
            isCanonical: isCanonical
        )
    }

    // MARK: - FeedItem

    static func makeFeedItem(
        id: UUID = UUID(),
        sourceID: UUID = TestFactory.sourceID,
        title: String = "Test Feed Item",
        link: URL = URL(string: "https://example.com/article")!,
        publishedAt: Date = Date(),
        fetchedAt: Date = Date(),
        excerpt: String = "Test excerpt with enough words for read time calculation in the tests.",
        imageURL: String? = nil,
        audioURL: String? = nil,
        videoURL: String? = nil,
        clusterID: UUID? = nil,
        isCanonical: Bool = false,
        velocityTier: VelocityTier = .article,
        relevanceScore: Double = 1.0,
        agedOut: Bool = false,
        riverVisible: Bool = true,
        simhashValue: UInt64 = 0
    ) -> FeedItem {
        FeedItem(
            id: id,
            sourceID: sourceID,
            title: title,
            link: link,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            excerpt: excerpt,
            imageURL: imageURL,
            audioURL: audioURL,
            videoURL: videoURL,
            clusterID: clusterID,
            isCanonical: isCanonical,
            velocityTier: velocityTier,
            relevanceScore: relevanceScore,
            agedOut: agedOut,
            riverVisible: riverVisible,
            simhashValue: simhashValue
        )
    }

    // MARK: - Source

    static func makeSource(
        id: UUID = TestFactory.sourceID,
        name: String = "Test Source",
        feedURL: String = "https://example.com/feed",
        categoryID: UUID = TestFactory.categoryID,
        isEnabled: Bool = true,
        isPaywalled: Bool = false,
        addedAt: Date = Date(),
        velocityTier: VelocityTier = .article,
        decayOverride: VelocityTier? = nil,
        preferUniqueStories: Bool = false
    ) -> Source {
        Source(
            id: id,
            name: name,
            feedURL: feedURL,
            categoryID: categoryID,
            isEnabled: isEnabled,
            isPaywalled: isPaywalled,
            addedAt: addedAt,
            velocityTier: velocityTier,
            decayOverride: decayOverride,
            preferUniqueStories: preferUniqueStories
        )
    }

    // MARK: - Category

    static func makeCategory(
        id: UUID = TestFactory.categoryID,
        name: String = "Test Category",
        icon: String = "folder.fill",
        sortOrder: Int = 0
    ) -> Category {
        Category(id: id, name: name, icon: icon, sortOrder: sortOrder)
    }

    // MARK: - SourceAffinityRecord

    static func makeAffinityRecord(
        sourceID: UUID = TestFactory.sourceID,
        affinityScore: Double = 0.0,
        eventCount: Int = 0,
        velocityTier: VelocityTier = .article,
        slotLimit: Int = 8
    ) -> SourceAffinityRecord {
        SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: affinityScore,
            eventCount: eventCount,
            velocityTier: velocityTier,
            slotLimit: slotLimit
        )
    }

    // MARK: - InteractionEvent

    static func makeEvent(
        sourceID: UUID = TestFactory.sourceID,
        itemID: UUID = UUID(),
        eventType: InteractionEventType = .articleOpen,
        dwellTime: TimeInterval? = nil
    ) -> InteractionEvent {
        InteractionEvent(
            sourceID: sourceID,
            itemID: itemID,
            eventType: eventType,
            dwellTime: dwellTime
        )
    }

    // MARK: - ExtractedArticle

    static func makeExtractedArticle(
        sourceURL: String = "https://example.com/article",
        title: String = "Test Article",
        nodes: [ContentNode] = [.paragraph(text: "Some article content here for testing.")],
        feedName: String = "Test Feed"
    ) -> ExtractedArticle {
        ExtractedArticle(
            id: UUID(),
            sourceURL: URL(string: sourceURL)!,
            title: title,
            author: "Test Author",
            publishDate: Date(),
            heroImageURL: nil,
            feedName: feedName,
            nodes: nodes,
            cachedAt: Date()
        )
    }
}

// MARK: - MockFeedDataService

final class MockFeedDataService: FeedDataService {
    var categories: [Category] = []
    var sources: [Source] = []
    var articles: [Article] = []

    func source(for id: UUID) -> Source? {
        sources.first { $0.id == id }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    func articlesForCategory(_ categoryID: UUID) -> [Article] {
        articles.filter { $0.categoryID == categoryID }
    }

    func articlesForSource(_ sourceID: UUID) -> [Article] {
        articles.filter { $0.sourceID == sourceID }
    }

    func unreadCountForCategory(_ categoryID: UUID) -> Int {
        articles.filter { $0.categoryID == categoryID && !$0.isRead }.count
    }

    func unreadCountForSource(_ sourceID: UUID) -> Int {
        articles.filter { $0.sourceID == sourceID && !$0.isRead }.count
    }

    func toggleBookmark(for articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isBookmarked.toggle()
        }
    }

    func markAsRead(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = true
        }
    }

    func markAsUnread(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = false
        }
    }

    func splitCluster(for articleID: UUID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }),
              let clusterID = articles[i].clusterID else { return }
        for j in articles.indices where articles[j].clusterID == clusterID {
            articles[j].clusterID = nil
            articles[j].clusterSize = 1
            articles[j].isCanonical = true
        }
    }
}
