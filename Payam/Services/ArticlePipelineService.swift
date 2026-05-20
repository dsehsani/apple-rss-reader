//
//  ArticlePipelineService.swift
//  Payam
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
//  Optimization: a four-level cache sits in front of the pipeline.
//    L1  NSCache (in-memory) — instant, survives the session
//    L0  cloud /v1/extractions cache — fast, shared across all users, skips the
//        expensive WKWebView fetch when another device has already extracted
//        the same URL. 422 (JS-rendered page, server gave up) and any 5xx
//        result are treated as a silent fall-through to L2/L3.
//    L2  SwiftData (disk)    — survives app relaunch
//    L3  WKWebView + Readability extraction (the slow path)
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

        // L0 — cloud extraction cache. Skips the WKWebView fetch when another
        // device has already extracted this URL. On 422 (JS-rendered, server
        // couldn't extract), 5xx, network error, or any decode failure we
        // silently fall through to L2/L3. CancellationError propagates so a
        // user-cancelled article navigation doesn't burn into the WebView path.
        if let cloud = await fetchFromCloud(item: item) {
            try? cache.save(article: cloud)
            let cost = (try? JSONEncoder().encode(cloud.nodes).count) ?? 1024
            Self.memoryCache.setObject(
                CacheEntry(article: cloud, cost: cost),
                forKey: cacheKey,
                cost: cost
            )
            return cloud
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

        let dedupedNodes = Self.dedupHeroImage(nodes: nodes, heroURL: readable.heroImageURL)

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

    // MARK: - L0 Cloud Extraction Cache

    /// Server-side extraction envelope returned by `GET /v1/extractions/{hash}`.
    /// On `status == "hit"` (or `"miss-extracted"`) the payload at `contentUrl`
    /// is the actual cached extraction. 422 / 502 / 500 responses raise an
    /// `HTTPStatusError` that we silently swallow into a fall-through.
    private struct ExtractEnvelope: Decodable {
        let status: String
        let contentUrl: String?
        let cachedAt: Int?
    }

    /// Shape of the JSON the server writes to S3. Mirrors the `payload` object
    /// constructed in payam-extract/src/extract.mjs.
    private struct ExtractedPayload: Decodable {
        let title: String
        let byline: String?
        let content: String          // HTML
        let excerpt: String?
        let lang: String?
        let heroImageURL: String?
        let sourceURL: String?
        let extractedAt: Int?
    }

    /// Off-MainActor network helper so the L0 request doesn't block the UI
    /// thread during a presigned-S3 fetch. All errors collapse to `nil`
    /// (silent fall-through to L2/L3); `Task.isCancelled` is honored
    /// cooperatively at the URLSession suspend points.
    private nonisolated func fetchExtractionPayload(item: RSSItem) async -> ExtractedPayload? {
        let urlString = item.sourceURL.absoluteString
        let hash = ArticleState.hash(urlString)

        var comps = URLComponents(
            url: CloudHTTP.extractBase.appendingPathComponent("v1/extractions/\(hash)"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "url", value: urlString)]
        guard let endpoint = comps?.url else { return nil }

        do {
            let (envelope, _) = try await CloudHTTP.get(endpoint, as: ExtractEnvelope.self)
            guard envelope.status == "hit" || envelope.status == "miss-extracted",
                  let contentUrlStr = envelope.contentUrl,
                  let contentURL = URL(string: contentUrlStr) else {
                return nil
            }
            let data = try await CloudHTTP.fetchPresigned(contentURL)
            return try JSONDecoder().decode(ExtractedPayload.self, from: data)
        } catch {
            // 422 (not_extractable), 502 (fetch_failed), 500 (persist_failed),
            // network error, decode error, NSURLErrorCancelled — all silent
            // fall-through to L2/L3.
            return nil
        }
    }

    /// Converts the server payload into a fully-formed `ExtractedArticle`.
    /// Returns nil on missing content or normalization failure so the caller
    /// falls through to the on-device extractor.
    private func fetchFromCloud(item: RSSItem) async -> ExtractedArticle? {
        guard let payload = await fetchExtractionPayload(item: item),
              !payload.content.isEmpty else { return nil }

        let heroURL = payload.heroImageURL.flatMap { URL(string: $0) }
        let readable = ReadableContent(
            title: payload.title,
            byline: payload.byline,
            content: payload.content,
            excerpt: payload.excerpt,
            heroImageURL: heroURL
        )

        let nodes: [ContentNode]
        do {
            nodes = try normalizer.normalize(content: readable)
        } catch {
            return nil
        }

        let dedupedNodes = Self.dedupHeroImage(nodes: nodes, heroURL: heroURL)

        return ExtractedArticle(
            id:           item.id,
            sourceURL:    item.sourceURL,
            title:        readable.title.isEmpty ? item.title : readable.title,
            author:       readable.byline ?? item.author,
            publishDate:  item.publishDate,
            heroImageURL: heroURL,
            feedName:     item.feedName,
            nodes:        dedupedNodes,
            cachedAt:     Date()
        )
    }

    /// Drops duplicate hero images by comparing URLs with query/fragment
    /// stripped. og:image URLs often differ from `<img src>` URLs only in CDN
    /// sizing params (e.g. `?w=1200`), causing a double hero on the article
    /// page if we keep both.
    private static func dedupHeroImage(nodes: [ContentNode], heroURL: URL?) -> [ContentNode] {
        func normalizedKey(_ url: URL) -> String {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.queryItems = nil
            comps?.fragment = nil
            return comps?.url?.absoluteString ?? url.absoluteString
        }
        var seenKeys = Set<String>()
        if let heroURL { seenKeys.insert(normalizedKey(heroURL)) }
        return nodes.filter { node in
            guard case .image(let url, _) = node else { return true }
            return seenKeys.insert(normalizedKey(url)).inserted
        }
    }

    // MARK: - Cache Maintenance

    /// Purges cached articles older than `days` days.
    func purgeOldCache(olderThan days: Int = 7) throws {
        try cache.purgeOldCache(olderThan: days)
    }
}
