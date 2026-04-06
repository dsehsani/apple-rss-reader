//
//  Article.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import os

// MARK: - CachePolicy

/// Central constants for cache retention and date validation.
enum CachePolicy: Sendable {
    /// How long read, non-bookmarked articles stay in the cache (days).
    static let cacheRetentionDays = 30
    /// How many days of articles the UI displays by default.
    static let displayWindowDays = 7
    /// Maximum hours into the future a publication date may be before it's rejected.
    static let maxFutureDateHours = 48
    /// Earliest plausible publication date for an RSS article.
    static let minimumValidDate: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        return Calendar.current.date(from: c)!
    }()
}

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
    /// Timestamp when this article was first fetched from the network.
    let fetchedAt: Date
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
        articleURL: String = "https://example.com",
        publishedAt: Date = Date(),
        fetchedAt: Date = Date(),
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
        self.articleURL = articleURL
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.isRead = isRead
        self.isBookmarked = isBookmarked
        self.readTimeMinutes = readTimeMinutes
        self.isPaywalled = isPaywalled
    }

    // Custom decoder so that cached JSON written before `isPaywalled` or
    // `fetchedAt` existed still decodes correctly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,   forKey: .id)
        title           = try c.decode(String.self, forKey: .title)
        excerpt         = try c.decode(String.self, forKey: .excerpt)
        sourceID        = try c.decode(UUID.self,   forKey: .sourceID)
        categoryID      = try c.decode(UUID.self,   forKey: .categoryID)
        imageURL        = try c.decodeIfPresent(String.self, forKey: .imageURL)
        articleURL      = try c.decode(String.self, forKey: .articleURL)
        publishedAt     = try c.decode(Date.self,   forKey: .publishedAt)
        // Backward compat: older JSON lacks fetchedAt — fall back to publishedAt.
        fetchedAt       = try c.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? publishedAt
        isRead          = try c.decode(Bool.self,   forKey: .isRead)
        isBookmarked    = try c.decode(Bool.self,   forKey: .isBookmarked)
        readTimeMinutes = try c.decode(Int.self,    forKey: .readTimeMinutes)
        isPaywalled     = try c.decodeIfPresent(Bool.self, forKey: .isPaywalled) ?? false
    }
}

// MARK: - Date Validation

private let articleLogger = Logger(subsystem: "com.openrss", category: "Article")

extension Article {
    /// Returns `publishedAt` if it's plausible, otherwise `fetchedAt`.
    /// Logs a warning when the original date is rejected.
    static func validatedPublishDate(
        _ candidate: Date,
        fetchedAt: Date,
        feedName: String
    ) -> Date {
        let maxFuture = Calendar.current.date(
            byAdding: .hour, value: CachePolicy.maxFutureDateHours, to: Date()
        ) ?? Date()

        if candidate > maxFuture {
            articleLogger.warning("Rejected future pubDate \(candidate) from feed \"\(feedName)\" — using fetchedAt")
            return fetchedAt
        }
        if candidate < CachePolicy.minimumValidDate {
            articleLogger.warning("Rejected old pubDate \(candidate) from feed \"\(feedName)\" — using fetchedAt")
            return fetchedAt
        }
        return candidate
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
