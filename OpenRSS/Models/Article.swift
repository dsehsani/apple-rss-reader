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
enum CachePolicy {
    /// How long read, non-bookmarked articles stay in the cache (days).
    nonisolated(unsafe) static let cacheRetentionDays = 30
    /// How many days of articles the UI displays by default.
    nonisolated(unsafe) static let displayWindowDays = 7
    /// Maximum hours into the future a publication date may be before it's rejected.
    nonisolated(unsafe) static let maxFutureDateHours = 48
    /// Earliest plausible publication date for an RSS article.
    nonisolated(unsafe) static let minimumValidDate: Date = {
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
    /// True when the article has fully decayed and aged out — excluded from the Today feed.
    var isArchived: Bool

    /// The cluster this article belongs to. nil = unclustered (standalone).
    /// Transient: not persisted to the JSON cache; recomputed on every refresh.
    var clusterID: UUID?

    /// Number of articles in this cluster (only meaningful on the canonical article).
    var clusterSize: Int

    /// True if this article is the representative card shown in the Today river.
    /// Non-canonical articles are hidden from the Today feed but visible in source/archive views.
    var isCanonical: Bool

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
        isPaywalled: Bool = false,
        isArchived: Bool = false,
        clusterID: UUID? = nil,
        clusterSize: Int = 1,
        isCanonical: Bool = true
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
        self.isArchived = isArchived
        self.clusterID = clusterID
        self.clusterSize = clusterSize
        self.isCanonical = isCanonical
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
        isArchived      = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        clusterID       = try c.decodeIfPresent(UUID.self, forKey: .clusterID)
        clusterSize     = try c.decodeIfPresent(Int.self, forKey: .clusterSize) ?? 1
        isCanonical     = try c.decodeIfPresent(Bool.self, forKey: .isCanonical) ?? true
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

// MARK: - Decay Scoring

extension Article {
    /// Exponential decay score based on article age and the source's half-life.
    /// Returns 1.0 for brand-new articles, 0.5 at one half-life, floored at 0.2.
    static func decayScore(publishedAt: Date, halfLifeHours: Double) -> Double {
        let hoursElapsed = max(0, Date().timeIntervalSince(publishedAt) / 3600)
        let freshnessMultiplier = UserDefaults.standard.double(forKey: "openrss.freshnessMultiplier")
        let multiplier = freshnessMultiplier > 0 ? freshnessMultiplier : 1.0
        let effectiveHalfLife = halfLifeHours * multiplier
        let lambda = log(2) / effectiveHalfLife
        return max(0.2, exp(-lambda * hoursElapsed))
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
