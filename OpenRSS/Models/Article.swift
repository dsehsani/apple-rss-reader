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
    let articleURL: String
    let publishedAt: Date
    var isRead: Bool
    var isBookmarked: Bool
    let readTimeMinutes: Int

    init(
        id: UUID = UUID(),
        title: String,
        excerpt: String,
        sourceID: UUID,
        categoryID: UUID,
        imageURL: String? = nil,
        articleURL: String = "https://example.com",
        publishedAt: Date = Date(),
        isRead: Bool = false,
        isBookmarked: Bool = false,
        readTimeMinutes: Int = 5
    ) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
        self.sourceID = sourceID
        self.categoryID = categoryID
        self.imageURL = imageURL
        self.articleURL = articleURL
        self.publishedAt = publishedAt
        self.isRead = isRead
        self.isBookmarked = isBookmarked
        self.readTimeMinutes = readTimeMinutes
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
