//
//  FeedItem.swift
//  OpenRSS
//
//  Phase 2a — Core pipeline model representing a single item from an RSS feed.
//  Stored in SQLite (feed_items table). This replaces Article as the internal
//  pipeline model; Article remains the UI-facing type via a conversion layer.
//

import Foundation

// MARK: - FeedItem

struct FeedItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceID: UUID
    let title: String
    let link: URL
    let publishedAt: Date
    let fetchedAt: Date

    // Excerpt / description from the feed (plain text, used for UI display)
    var excerpt: String

    // Image URL from the feed (hero image)
    var imageURL: String?

    // Audio enclosure URL (e.g. podcast episodes). Nil for most items.
    var audioURL: String?

    // Author from the feed
    var author: String?

    // Clustering (Phase 2b)
    var clusterID: UUID?
    var isCanonical: Bool

    // Scoring
    var velocityTier: VelocityTier
    var relevanceScore: Double

    // Lifecycle
    var agedOut: Bool
    var riverVisible: Bool

    // Dedup / clustering support
    var simhashValue: UInt64

    // Embedding (Phase 2b — nil until computed)
    var embeddingVector: [Float]?

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        title: String,
        link: URL,
        publishedAt: Date,
        fetchedAt: Date = Date(),
        excerpt: String = "",
        imageURL: String? = nil,
        audioURL: String? = nil,
        author: String? = nil,
        clusterID: UUID? = nil,
        isCanonical: Bool = false,
        velocityTier: VelocityTier = .article,
        relevanceScore: Double = 1.0,
        agedOut: Bool = false,
        riverVisible: Bool = true,
        simhashValue: UInt64 = 0,
        embeddingVector: [Float]? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.link = link
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.excerpt = excerpt
        self.imageURL = imageURL
        self.audioURL = audioURL
        self.author = author
        self.clusterID = clusterID
        self.isCanonical = isCanonical
        self.velocityTier = velocityTier
        self.relevanceScore = relevanceScore
        self.agedOut = agedOut
        self.riverVisible = riverVisible
        self.simhashValue = simhashValue
        self.embeddingVector = embeddingVector
    }
}

// MARK: - Hashable (manual — embeddingVector excluded)

extension FeedItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
            && lhs.sourceID == rhs.sourceID
            && lhs.title == rhs.title
            && lhs.link == rhs.link
            && lhs.relevanceScore == rhs.relevanceScore
            && lhs.agedOut == rhs.agedOut
            && lhs.riverVisible == rhs.riverVisible
    }
}

// MARK: - FeedItem → Article Conversion

extension FeedItem {

    /// Converts a FeedItem to the legacy Article type so existing views keep working.
    ///
    /// - Parameters:
    ///   - categoryID: The category the source belongs to (looked up externally).
    /// - Returns: An Article suitable for ArticleCardView and related UI.
    func toArticle(categoryID: UUID) -> Article {
        Article(
            id: id,
            title: title,
            excerpt: excerpt,
            sourceID: sourceID,
            categoryID: categoryID,
            imageURL: imageURL,
            audioURL: audioURL,
            articleURL: link.absoluteString,
            publishedAt: publishedAt,
            isRead: false,
            isBookmarked: false,
            readTimeMinutes: estimatedReadTime,
            isPaywalled: false
        )
    }

    /// Rough read-time estimate from the excerpt word count.
    private var estimatedReadTime: Int {
        let wordCount = excerpt.split { $0.isWhitespace || $0.isNewline }.count
        return max(1, min(30, wordCount / 200))
    }
}
