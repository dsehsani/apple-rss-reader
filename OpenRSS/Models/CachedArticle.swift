//
//  CachedArticle.swift
//  OpenRSS
//
//  Phase 6 — SwiftData model for persisting extracted articles.
//  `serializedNodes` stores a JSON-encoded [ContentNode] array.
//

import Foundation
import SwiftData

// MARK: - CachedArticle

@Model
final class CachedArticle {

    // MARK: - Stored Attributes

    @Attribute(.unique) var id: UUID
    var title:            String
    var author:           String?
    var publishDate:      Date?
    var heroImageURL:     String?   // stored as String; converted to URL on read
    var feedName:         String
    var sourceURL:        String    // stored as String; converted to URL on read
    var cachedAt:         Date
    var serializedNodes:  Data      // JSON-encoded [ContentNode]

    // MARK: - Init

    init(
        id:              UUID,
        title:           String,
        author:          String?,
        publishDate:     Date?,
        heroImageURL:    URL?,
        feedName:        String,
        sourceURL:       URL,
        cachedAt:        Date,
        serializedNodes: Data
    ) {
        self.id              = id
        self.title           = title
        self.author          = author
        self.publishDate     = publishDate
        self.heroImageURL    = heroImageURL?.absoluteString
        self.feedName        = feedName
        self.sourceURL       = sourceURL.absoluteString
        self.cachedAt        = cachedAt
        self.serializedNodes = serializedNodes
    }
}
