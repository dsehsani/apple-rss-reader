//
//  FeedIngestService.swift
//  Payam
//
//  Phase 2 — Stage 1 of the River Pipeline, now backed by the deployed
//  /v1/river endpoint instead of direct RSS polling. Cloud sync is the
//  single source of items; on a sync failure we propagate the throw so
//  `RiverViewModel` can surface a "couldn't reach server" banner.
//

import Foundation

// MARK: - FeedIngestService

final class FeedIngestService: Sendable {

    // MARK: - Dependencies

    private let store = SQLiteStore.shared
    private let cloudSync = CloudFeedSyncService()

    // MARK: - Public API

    /// Pulls new items from the cloud `/v1/river` endpoint, dedup-inserts them
    /// into SQLite, and refreshes each source's velocity-affinity record.
    ///
    /// Throws on network/server failure so the caller can distinguish
    /// "sync succeeded with zero new items" from "sync failed".
    func ingest(
        sources: [Source],
        velocityOverrides: [UUID: VelocityTier] = [:]
    ) async throws -> [FeedItem] {
        let enabledSources = sources.filter(\.isEnabled)
        guard !enabledSources.isEmpty else { return [] }

        let newItems = try await cloudSync.sync(sources: enabledSources)

        // Refresh affinity rows so the rest of the pipeline (rate-gating, scoring)
        // sees up-to-date velocity tiers. Use the override if present; otherwise
        // fall back to the tier the cloud row was tagged with, then to whatever
        // we can infer from history.
        let bySource = Dictionary(grouping: newItems, by: \.sourceID)
        for source in enabledSources {
            let items = bySource[source.id] ?? []
            let tier = velocityOverrides[source.id]
                ?? items.first?.velocityTier
                ?? inferVelocityTier(sourceID: source.id)
            updateSourceAffinity(source: source, tier: tier)
        }

        return newItems
    }

    // MARK: - Velocity Tier Inference

    /// Infers velocity tier from historical publish frequency in SQLite.
    private func inferVelocityTier(sourceID: UUID) -> VelocityTier {
        if let record = store.fetchAffinity(forSource: sourceID),
           record.velocityTier != .article || record.eventCount > 0 {
            return record.velocityTier
        }

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
}

// MARK: - Deterministic UUID

extension UUID {
    /// Creates a deterministic UUID v5-like hash from a name string.
    /// Mirrors `deterministicUUID` in payam-polling/src/lib/keys.mjs (two FNV-1a
    /// passes — forward then reversed — into the two 64-bit halves of the UUID).
    init(name: String) {
        let data = Data(name.utf8)
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        var h: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in data {
            h ^= UInt64(byte)
            h &*= 1099511628211 // FNV prime
        }
        for i in 0..<8 {
            hash[i] = UInt8((h >> (i * 8)) & 0xFF)
        }
        for byte in data.reversed() {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        for i in 0..<8 {
            hash[8 + i] = UInt8((h >> (i * 8)) & 0xFF)
        }
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
