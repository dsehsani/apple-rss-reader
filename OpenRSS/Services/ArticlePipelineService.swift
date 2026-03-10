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
//  Optimization: a two-level cache sits in front of the pipeline.
//    L1  NSCache (in-memory) — instant, survives the session
//    L2  SwiftData (disk)    — survives app relaunch
//  Only if both miss do we run the expensive extraction pipeline.
//

import Foundation
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ArticlePipelineService

@MainActor
final class ArticlePipelineService {

    // MARK: - Sub-services

    private let extractor:  ReadabilityExtractionService
    private let normalizer: ContentNormalizerService
    private let cache:      ArticleCacheService

    // MARK: - L1 Memory Cache

    /// In-memory cache keyed by article UUID string.
    /// Repeat opens within the same session are effectively instant (~0.05s).
    private static let memoryCache = NSCache<NSString, CacheEntry>()

    private static var memoryCacheConfigured = false

    private static func configureMemoryCacheOnce() {
        guard !memoryCacheConfigured else { return }
        memoryCacheConfigured = true
        memoryCache.totalCostLimit = 30 * 1024 * 1024  // 30 MB
        memoryCache.countLimit = 50

        // Flush on memory warning to avoid jetsam termination.
        // NSCache is thread-safe internally; nonisolated(unsafe) silences
        // the Sendable diagnostic for the closure capture.
        nonisolated(unsafe) let cache = memoryCache
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            cache.removeAllObjects()
        }
    }

    /// Wrapper so NSCache can hold a Swift struct.
    private final class CacheEntry: NSObject {
        let article: ExtractedArticle
        let cost: Int
        init(article: ExtractedArticle, cost: Int) {
            self.article = article
            self.cost = cost
        }
    }

    // MARK: - Init

    init(context: ModelContext) {
        self.extractor  = ReadabilityExtractionService()
        self.normalizer = ContentNormalizerService()
        self.cache      = ArticleCacheService(context: context)
        Self.configureMemoryCacheOnce()
    }

    // MARK: - Public API

    /// Processes a single RSS item through the full pipeline.
    /// Returns a cached result immediately if one exists (memory or disk).
    func process(item: RSSItem) async throws -> ExtractedArticle {
        let cacheKey = item.id.uuidString as NSString

        // L1 — memory cache (instant)
        if let entry = Self.memoryCache.object(forKey: cacheKey) {
            return entry.article
        }

        // L2 — SwiftData disk cache (fast, promotes to L1)
        if let cached = try cache.load(id: item.id) {
            let cost = (try? JSONEncoder().encode(cached.nodes).count) ?? 1024
            Self.memoryCache.setObject(
                CacheEntry(article: cached, cost: cost),
                forKey: cacheKey,
                cost: cost
            )
            return cached
        }

        // Full pipeline — cache miss
        // Phase 3 — WebView navigates to the live URL, JS renders, Readability extracts
        let readable = try await extractor.extract(sourceURL: item.sourceURL)

        // Phase 4 — normalise cleaned HTML into typed ContentNode array
        let nodes = try normalizer.normalize(content: readable)

        // Deduplicate image nodes
        var seenImageURLs = Set<URL>()
        if let heroURL = readable.heroImageURL { seenImageURLs.insert(heroURL) }
        let dedupedNodes = nodes.filter { node in
            guard case .image(let url, _) = node else { return true }
            return seenImageURLs.insert(url).inserted
        }

        // Build the ExtractedArticle
        let extracted = ExtractedArticle(
            id:           item.id,
            sourceURL:    item.sourceURL,
            title:        readable.title.isEmpty ? item.title : readable.title,
            author:       readable.byline ?? item.author,
            publishDate:  item.publishDate,
            heroImageURL: readable.heroImageURL,
            feedName:     item.feedName,
            nodes:        dedupedNodes,
            cachedAt:     Date()
        )

        // Write to both cache layers
        try cache.save(article: extracted)
        let cost = (try? JSONEncoder().encode(dedupedNodes).count) ?? 1024
        Self.memoryCache.setObject(
            CacheEntry(article: extracted, cost: cost),
            forKey: cacheKey,
            cost: cost
        )

        return extracted
    }

    // MARK: - Cache Maintenance

    /// Purges cached articles older than `days` days.
    func purgeOldCache(olderThan days: Int = 7) throws {
        try cache.purgeOldCache(olderThan: days)
    }
}
