//
//  ArticleCacheService.swift
//  OpenRSS
//
//  Phase 6 — Caching
//
//  Persists fully-extracted articles using SwiftData so the expensive
//  pipeline (phases 2-4) is skipped on subsequent views.
//
//  All methods are @MainActor because SwiftData's ModelContext must be
//  accessed on the main actor.
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol ArticleCacheServiceProtocol: Sendable {
    @MainActor func save(article: ExtractedArticle) throws
    @MainActor func load(id: UUID) throws -> ExtractedArticle?
    @MainActor func isCached(id: UUID) -> Bool
    @MainActor func purgeOldCache(olderThan days: Int) throws

}

// MARK: - Errors

enum ArticleCacheError: LocalizedError {
    case contextUnavailable
    case decodeFailed(Error)
    case encodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .contextUnavailable:
            return "SwiftData context is not available."
        case .decodeFailed(let e):
            return "Failed to decode cached article: \(e.localizedDescription)"
        case .encodeFailed(let e):
            return "Failed to encode article for caching: \(e.localizedDescription)"
        }
    }
}

// MARK: - ArticleCacheService

@MainActor
final class ArticleCacheService: ArticleCacheServiceProtocol {

    // MARK: - Dependencies

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Save

    func save(article: ExtractedArticle) throws {
        // Encode ContentNode array
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(article.nodes)
        } catch {
            throw ArticleCacheError.encodeFailed(error)
        }

        // Upsert: delete old record if present, then insert fresh
        if let existing = try fetchRecord(id: article.id) {
            context.delete(existing)
        }

        let record = CachedArticle(
            id:              article.id,
            title:           article.title,
            author:          article.author,
            publishDate:     article.publishDate,
            heroImageURL:    article.heroImageURL,
            feedName:        article.feedName,
            sourceURL:       article.sourceURL,
            cachedAt:        article.cachedAt,
            serializedNodes: data
        )
        context.insert(record)
        try context.save()
    }

    // MARK: - Load

    func load(id: UUID) throws -> ExtractedArticle? {
        guard let record = try fetchRecord(id: id) else { return nil }
        return try decode(record: record)
    }

    // MARK: - isCached

    func isCached(id: UUID) -> Bool {
        (try? fetchRecord(id: id)) != nil
    }

    // MARK: - Purge

    func purgeOldCache(olderThan days: Int = CachePolicy.cacheRetentionDays) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<CachedArticle>(
            predicate: #Predicate { $0.cachedAt < cutoff }
        )
        let old = try context.fetch(descriptor)
        for record in old { context.delete(record) }
        if !old.isEmpty { try context.save() }
    }

    // MARK: - Private Helpers

    private func fetchRecord(id: UUID) throws -> CachedArticle? {
        let descriptor = FetchDescriptor<CachedArticle>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func decode(record: CachedArticle) throws -> ExtractedArticle {
        let decoder = JSONDecoder()
        let nodes: [ContentNode]
        do {
            nodes = try decoder.decode([ContentNode].self, from: record.serializedNodes)
        } catch {
            throw ArticleCacheError.decodeFailed(error)
        }

        guard let sourceURL = URL(string: record.sourceURL) else {
            throw ArticleCacheError.decodeFailed(
                NSError(domain: "ArticleCache", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid sourceURL in cache"])
            )
        }

        return ExtractedArticle(
            id:          record.id,
            sourceURL:   sourceURL,
            title:       record.title,
            author:      record.author,
            publishDate: record.publishDate,
            heroImageURL: record.heroImageURL.flatMap { URL(string: $0) },
            feedName:    record.feedName,
            nodes:       nodes,
            cachedAt:    record.cachedAt
        )
    }
}
