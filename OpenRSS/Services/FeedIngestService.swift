//
//  FeedIngestService.swift
//  OpenRSS
//
//  Phase 2a — Stage 1 of the River Pipeline.
//  Fetches RSS feeds, parses them into FeedItem structs,
//  deduplicates against the SQLite store, and assigns velocity tiers.
//

import Foundation

// MARK: - FeedIngestService

final class FeedIngestService: Sendable {

    // MARK: - Dependencies

    private let rssService = RSSService()
    private let store = SQLiteStore.shared

    // MARK: - ETag / Last-Modified Cache

    /// In-memory conditional GET cache keyed by feed URL string.
    /// Stores (ETag, Last-Modified, Data) from the previous successful fetch.
    private let conditionalCache = ConditionalCache()

    // MARK: - Public API

    /// Ingests all enabled sources and returns newly inserted FeedItems.
    ///
    /// - Parameters:
    ///   - sources: The user's subscribed feed sources.
    ///   - velocityOverrides: Manual velocity tier overrides keyed by source ID.
    /// - Returns: Array of new (deduplicated) FeedItems.
    func ingest(
        sources: [Source],
        velocityOverrides: [UUID: VelocityTier] = [:]
    ) async -> [FeedItem] {
        var allNewItems: [FeedItem] = []

        for source in sources where source.isEnabled {
            guard let feedURL = URL(string: source.feedURL) else { continue }

            do {
                let (data, changed) = try await fetchWithConditionalGET(url: feedURL)
                guard changed, let data else { continue }

                let parsed = try await rssService.parseFeed(from: data)

                // For YouTube feeds, use existing YouTube parser for supplemental data
                var youtubeExtras: [String: YouTubeAtomParser.VideoMeta] = [:]
                if YouTubeService.isYouTubeURL(feedURL) {
                    youtubeExtras = YouTubeAtomParser().parse(data: data)
                }

                // Determine velocity tier
                let tier = velocityOverrides[source.id]
                    ?? inferVelocityTier(sourceID: source.id)

                // Convert parsed articles to FeedItems
                let feedItems = parsed.compactMap { p -> FeedItem? in
                    convertToFeedItem(
                        parsed: p,
                        source: source,
                        velocityTier: tier,
                        youtubeExtras: youtubeExtras
                    )
                }

                // Deduplicate against existing items in SQLite
                let candidateIDs = Set(feedItems.map(\.id))
                let existingIDs = store.existingItemIDs(from: candidateIDs)
                let newItems = feedItems.filter { !existingIDs.contains($0.id) }

                if !newItems.isEmpty {
                    store.upsertFeedItems(newItems)
                    print("✅ Inserted \(newItems.count) items from \(source.name)")
                    allNewItems.append(contentsOf: newItems)
                }

                // Update velocity tier in affinity table
                updateSourceAffinity(source: source, tier: tier)

            } catch {
                // Failed to fetch or parse this source — continue with others.
                print("❌ Failed to ingest \(source.name): \(error)")
                continue
            }
        }

        return allNewItems
    }

    // MARK: - Conditional GET

    /// Fetches feed data using ETag/Last-Modified headers when available.
    /// Returns (data, changed). If the server returns 304 Not Modified, returns (nil, false).
    private func fetchWithConditionalGET(url: URL) async throws -> (Data?, Bool) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("OpenRSS/2.0 (iOS; River)", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "application/rss+xml, application/atom+xml, application/json, text/xml, */*",
            forHTTPHeaderField: "Accept"
        )

        // Apply cached conditional headers
        let key = url.absoluteString
        if let cached = conditionalCache.get(key) {
            if let etag = cached.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = cached.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RSSServiceError.invalidResponse
        }

        if http.statusCode == 304 {
            return (nil, false)
        }

        guard (200...299).contains(http.statusCode) else {
            throw RSSServiceError.invalidResponse
        }

        // Cache the conditional headers for next time
        let etag = http.value(forHTTPHeaderField: "ETag")
        let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
        conditionalCache.set(key, etag: etag, lastModified: lastModified)

        return (data, true)
    }

    // MARK: - Conversion

    /// Converts a ParsedArticle to a FeedItem, generating a stable ID from the link.
    /// Handles items with missing links gracefully (falls back to source website URL).
    private func convertToFeedItem(
        parsed: ParsedArticle,
        source: Source,
        velocityTier: VelocityTier,
        youtubeExtras: [String: YouTubeAtomParser.VideoMeta]
    ) -> FeedItem? {
        guard let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }

        let linkStr = (parsed.link ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve the link URL: prefer the item's own link, fall back to source website.
        let link: URL
        if !linkStr.isEmpty, let parsedURL = URL(string: linkStr) {
            link = parsedURL
        } else if let sourceURL = URL(string: source.websiteURL) {
            link = sourceURL
        } else {
            link = URL(string: "https://example.com")!
        }

        // Stable ID: deterministic UUID from source + link (or title when link is absent).
        // Matches the dedup key format used by SwiftDataService.refreshAllFeeds().
        let stableKey: String
        if !linkStr.isEmpty {
            stableKey = "\(source.id.uuidString)|\(linkStr)"
        } else {
            stableKey = "\(source.id.uuidString)|\(title)"
        }
        let id = UUID(name: stableKey)

        // YouTube supplemental data
        let ytMeta = youtubeExtras[linkStr]
        let rawExcerpt = parsed.description ?? ytMeta?.description ?? ""
        let excerpt = Self.plainText(rawExcerpt)

        // Image priority: FeedKit > YouTube parser > first <img> in description
        var imageURL = parsed.imageURL ?? ytMeta?.thumbnailURL
        if imageURL == nil, YouTubeService.isYouTubeVideoOrShortURL(linkStr) {
            imageURL = YouTubeService.videoID(from: linkStr)
                .flatMap { YouTubeService.thumbnailURL(videoID: $0)?.absoluteString }
        }

        return FeedItem(
            id: id,
            sourceID: source.id,
            title: title,
            link: link,
            publishedAt: parsed.publicationDate ?? Date(),
            fetchedAt: Date(),
            excerpt: excerpt,
            imageURL: imageURL,
            audioURL: parsed.audioURL,
            author: parsed.author,
            velocityTier: velocityTier,
            simhashValue: SimHash.compute(title)
        )
    }

    // MARK: - Velocity Tier Inference

    /// Infers velocity tier from historical publish frequency in SQLite.
    private func inferVelocityTier(sourceID: UUID) -> VelocityTier {
        // Check if we already have an affinity record with a tier
        if let record = store.fetchAffinity(forSource: sourceID),
           record.velocityTier != .article || record.eventCount > 0 {
            return record.velocityTier
        }

        // Compute from historical items
        let items = store.fetchItems(forSource: sourceID)
        guard items.count >= 2 else { return .article }

        let sorted = items.sorted { $0.publishedAt < $1.publishedAt }
        guard let earliest = sorted.first?.publishedAt,
              let latest = sorted.last?.publishedAt else { return .article }

        let daySpan = max(1, latest.timeIntervalSince(earliest) / 86400)
        let avgPerDay = Double(items.count) / daySpan

        return VelocityTier.infer(averageItemsPerDay: avgPerDay)
    }

    /// Updates or creates the source affinity record with the inferred tier.
    private func updateSourceAffinity(source: Source, tier: VelocityTier) {
        if var existing = store.fetchAffinity(forSource: source.id) {
            existing.velocityTier = tier
            existing.slotLimit = tier.defaultSlotLimit
            store.upsertAffinity(existing)
        } else {
            let record = SourceAffinityRecord(
                sourceID: source.id,
                velocityTier: tier,
                slotLimit: tier.defaultSlotLimit
            )
            store.upsertAffinity(record)
        }
    }

    // MARK: - Helpers

    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&#39;",   with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Deterministic UUID

extension UUID {
    /// Creates a deterministic UUID v5-like hash from a name string.
    /// Uses SHA-256 truncated to 128 bits with version/variant bits set.
    init(name: String) {
        let data = Data(name.utf8)
        // Simple FNV-1a based approach for deterministic UUID
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        var h: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in data {
            h ^= UInt64(byte)
            h &*= 1099511628211 // FNV prime
        }
        // Fill first 8 bytes
        for i in 0..<8 {
            hash[i] = UInt8((h >> (i * 8)) & 0xFF)
        }
        // Second pass for remaining bytes
        for byte in data.reversed() {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        for i in 0..<8 {
            hash[8 + i] = UInt8((h >> (i * 8)) & 0xFF)
        }
        // Set version (4) and variant (RFC 4122)
        hash[6] = (hash[6] & 0x0F) | 0x50  // version 5
        hash[8] = (hash[8] & 0x3F) | 0x80  // variant

        self = UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}

// MARK: - SimHash

/// FNV-1a based SimHash for title deduplication.
enum SimHash {

    /// Computes a 64-bit SimHash from the input text.
    static func compute(_ text: String) -> UInt64 {
        let tokens = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
        var vector = [Int](repeating: 0, count: 64)
        for token in tokens {
            let hash = fnv1a(token)
            for bit in 0..<64 {
                vector[bit] += (hash >> bit) & 1 == 1 ? 1 : -1
            }
        }
        return vector.enumerated().reduce(UInt64(0)) { result, pair in
            pair.element > 0 ? result | (1 << pair.offset) : result
        }
    }

    /// Hamming distance between two SimHash values.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// FNV-1a hash — deterministic, unlike Swift's built-in .hashValue.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

// MARK: - ConditionalCache

/// Thread-safe cache for ETag / Last-Modified headers.
private final class ConditionalCache: @unchecked Sendable {
    struct Entry {
        let etag: String?
        let lastModified: String?
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func set(_ key: String, etag: String?, lastModified: String?) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = Entry(etag: etag, lastModified: lastModified)
    }
}
