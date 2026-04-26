//
//  Article.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation

/// Represents an RSS article/feed item
struct Article: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let excerpt: String
    let sourceID: UUID
    let categoryID: UUID
    let imageURL: String?
    /// Audio enclosure URL from the RSS feed (e.g. podcast episodes). Nil for most articles.
    let audioURL: String?
    let articleURL: String
    let publishedAt: Date
    var isRead: Bool
    var isBookmarked: Bool
    let readTimeMinutes: Int
    /// Set to true when post-pipeline detection finds a subscription prompt in the article content.
    var isPaywalled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        excerpt: String,
        sourceID: UUID,
        categoryID: UUID,
        imageURL: String? = nil,
        audioURL: String? = nil,
        articleURL: String = "https://example.com",
        publishedAt: Date = Date(),
        isRead: Bool = false,
        isBookmarked: Bool = false,
        readTimeMinutes: Int = 5,
        isPaywalled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.sourceID = sourceID
        self.categoryID = categoryID
        self.imageURL = imageURL
        self.audioURL = audioURL
        self.articleURL = articleURL
        self.publishedAt = publishedAt
        self.isRead = isRead
        self.isBookmarked = isBookmarked
        self.readTimeMinutes = readTimeMinutes
        self.isPaywalled = isPaywalled
    }

    // Custom decoder so that cached JSON written before `isPaywalled` or `audioURL` existed
    // still decodes correctly (defaults to nil/false when the key is absent).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,   forKey: .id)
        title           = try c.decode(String.self, forKey: .title)
        excerpt         = try c.decode(String.self, forKey: .excerpt)
        sourceID        = try c.decode(UUID.self,   forKey: .sourceID)
        categoryID      = try c.decode(UUID.self,   forKey: .categoryID)
        imageURL        = try c.decodeIfPresent(String.self, forKey: .imageURL)
        audioURL        = try c.decodeIfPresent(String.self, forKey: .audioURL)
        articleURL      = try c.decode(String.self, forKey: .articleURL)
        publishedAt     = try c.decode(Date.self,   forKey: .publishedAt)
        isRead          = try c.decode(Bool.self,   forKey: .isRead)
        isBookmarked    = try c.decode(Bool.self,   forKey: .isBookmarked)
        readTimeMinutes = try c.decode(Int.self,    forKey: .readTimeMinutes)
        isPaywalled     = try c.decodeIfPresent(Bool.self, forKey: .isPaywalled) ?? false
    }
}

// MARK: - Date Formatting Extension

extension Article {
    /// Returns a human-readable relative time string (e.g., "2h ago", "3d ago")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishedAt, relativeTo: Date())
    }
}
