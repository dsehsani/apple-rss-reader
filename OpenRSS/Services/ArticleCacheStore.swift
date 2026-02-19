//
//  ArticleCacheStore.swift
//  OpenRSS
//
//  Interim JSON cache for fetched articles.
//
//  Architecture note:
//  This is a lightweight file-based cache that sits between the live RSS fetch
//  and the UI. It lets articles appear immediately on launch without a network
//  round-trip, mirrors the pattern used by NetNewsWire and Reeder.
//
//  Migration path → SQLite:
//  When we move to GRDB or SQLite.swift, replace the save/load bodies here
//  (or add a `ArticlePersisting` protocol and swap implementations). The rest
//  of the codebase — SwiftDataService and TodayViewModel — calls only
//  ArticleCacheStore.save / .load / .clear, so the blast radius is tiny.
//

import Foundation

// MARK: - ArticleCacheStore

/// Saves and loads the current in-memory article list to/from a JSON file
/// in the system Caches directory. Articles older than 7 days are dropped on
/// load to keep the cache from growing unboundedly.
///
/// Thread-safety: all methods are synchronous and cheap; call them from a
/// background context if the article count grows very large (10k+).
enum ArticleCacheStore {

    // MARK: - Constants

    private static let fileName   = "openrss_articles.json"
    private static let maxAgeDays = 7

    // MARK: - Cache URL

    private static var cacheURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    // MARK: - Public API

    /// Encodes `articles` to JSON and atomically writes the file.
    /// Silently no-ops on encoding failure (the next refresh will succeed).
    static func save(_ articles: [Article]) {
        do {
            let data = try JSONEncoder().encode(articles)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("ArticleCacheStore: save failed — \(error)")
        }
    }

    /// Reads the JSON file and returns articles published within the past 7 days.
    /// Returns an empty array if the file doesn't exist or can't be decoded.
    static func load() -> [Article] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        guard let articles = try? JSONDecoder().decode([Article].self, from: data) else {
            return []
        }
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -maxAgeDays, to: Date()
        ) ?? Date()
        return articles.filter { $0.publishedAt >= cutoff }
    }

    /// Removes the cache file entirely.
    /// Call this when the user deletes all feeds or resets app data.
    static func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
