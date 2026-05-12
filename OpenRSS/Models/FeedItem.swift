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

    // Video enclosure URL (e.g. video podcasts, video news segments). Nil for most items.
    var videoURL: String?

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
        videoURL: String? = nil,
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
        self.videoURL = videoURL
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

    /// Vimeo article pages almost always need **per-video** `og:image`; RSS-derived URLs are
    /// often channel branding reused across entries. Those stale URLs survive forever in SQLite
    /// because ingest only inserts **new** item IDs — existing rows are never refreshed.
    ///
    /// For Vimeo hosts we intentionally pass `nil` here so `ArticleCardView` runs OG resolution.
    /// Blog/help/settings URLs keep feed-provided artwork when present.
    private static func shouldResolveVimeoHeroViaOG(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        guard host == "vimeo.com" || host == "www.vimeo.com" || host == "player.vimeo.com" else {
            return false
        }
        let path = url.path
        if path.hasPrefix("/blog") || path.hasPrefix("/help") || path.hasPrefix("/settings") {
            return false
        }
        return true
    }

    /// Converts a FeedItem to the legacy Article type so existing views keep working.
    ///
    /// - Parameters:
    ///   - categoryID: The category the source belongs to (looked up externally).
    /// - Returns: An Article suitable for ArticleCardView and related UI.
    func toArticle(categoryID: UUID) -> Article {
        let heroURL: String? = Self.shouldResolveVimeoHeroViaOG(link) ? nil : imageURL

        return Article(
            id: id,
            title: title,
            excerpt: excerpt,
            sourceID: sourceID,
            categoryID: categoryID,
            imageURL: heroURL,
            audioURL: audioURL,
            videoURL: videoURL,
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
