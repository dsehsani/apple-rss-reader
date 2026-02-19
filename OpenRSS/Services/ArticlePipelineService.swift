//
//  ArticlePipelineService.swift
//  OpenRSS
//
//  Orchestrates the article pipeline:
//
//    Phase 1  RSSParserService        — done upstream (produces RSSItem)
//    Phase 3  ReadabilityExtractionService — WebView loads the live URL,
//                                           JS renders, Readability extracts
//    Phase 4  ContentNormalizerService — cleaned HTML → [ContentNode]
//    Phase 5  ArticleReaderView       — UI layer
//    Phase 6  ArticleCacheService     — cache; skip 3-4 on repeat opens
//
//  Note: Phase 2 (ContentFetcherService / raw HTML fetch) is intentionally
//  skipped.  Modern sites render content via JavaScript, so the WebView must
//  navigate to the real URL to get a live network context.
//

import Foundation
import SwiftData

// MARK: - ArticlePipelineService

@MainActor
final class ArticlePipelineService {

    // MARK: - Sub-services

    private let extractor:  ReadabilityExtractionService
    private let normalizer: ContentNormalizerService
    private let cache:      ArticleCacheService

    // MARK: - Init

    init(context: ModelContext) {
        self.extractor  = ReadabilityExtractionService()
        self.normalizer = ContentNormalizerService()
        self.cache      = ArticleCacheService(context: context)
    }

    // MARK: - Public API

    /// Processes a single RSS item through the full pipeline.
    /// Returns a cached result immediately if one exists.
    func process(item: RSSItem) async throws -> ExtractedArticle {

        // Phase 6a — check cache first
        if let cached = try cache.load(id: item.id) {
            return cached
        }

        // Phase 3 — WebView navigates to the live URL, JS renders, Readability extracts
        let readable = try await extractor.extract(sourceURL: item.sourceURL)

        // Phase 4 — normalise cleaned HTML into typed ContentNode array
        let nodes = try normalizer.normalize(content: readable)

        // Build the ExtractedArticle
        let extracted = ExtractedArticle(
            id:           item.id,
            sourceURL:    item.sourceURL,
            title:        readable.title.isEmpty ? item.title : readable.title,
            author:       readable.byline ?? item.author,
            publishDate:  item.publishDate,
            heroImageURL: readable.heroImageURL,
            feedName:     item.feedName,
            nodes:        nodes,
            cachedAt:     Date()
        )

        // Phase 6b — cache the result
        try cache.save(article: extracted)

        return extracted
    }

    // MARK: - Cache Maintenance

    /// Purges cached articles older than `days` days.
    func purgeOldCache(olderThan days: Int = 7) throws {
        try cache.purgeOldCache(olderThan: days)
    }
}
