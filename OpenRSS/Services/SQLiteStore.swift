//
//  SQLiteStore.swift
//  OpenRSS
//
//  Phase 2a — Lightweight SQLite wrapper using the raw C API.
//  Manages the feed_items, source_affinity, and interaction_events tables.
//  WAL mode for concurrent reads. All writes are serialized on a private queue.
//

import Foundation
import SQLite3

// MARK: - SQLiteStore

final class SQLiteStore: Sendable {

    // MARK: - Singleton

    static let shared = SQLiteStore()

    // MARK: - Private State

    /// Database pointer — access only from `queue`.
    private let db: DatabaseHandle

    /// Serial queue for all database writes.
    private let queue = DispatchQueue(label: "com.openrss.sqlitestore", qos: .userInitiated)

    // MARK: - Init

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("OpenRSS", isDirectory: true)
        try? fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("river.sqlite").path

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &handle, flags, nil) == SQLITE_OK, let h = handle else {
            fatalError("SQLiteStore: failed to open database at \(dbPath)")
        }
        self.db = DatabaseHandle(pointer: h)

        // Enable WAL mode and create tables.
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        createTables()
    }

    deinit {
        sqlite3_close(db.pointer)
    }

    // MARK: - Schema

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS feed_items (
                id               TEXT PRIMARY KEY,
                source_id        TEXT NOT NULL,
                title            TEXT NOT NULL,
                link             TEXT NOT NULL,
                published_at     INTEGER NOT NULL,
                fetched_at       INTEGER NOT NULL,
                excerpt          TEXT NOT NULL DEFAULT '',
                image_url        TEXT,
                author           TEXT,
                cluster_id       TEXT,
                is_canonical     INTEGER DEFAULT 0,
                velocity_tier    TEXT NOT NULL,
                relevance_score  REAL DEFAULT 1.0,
                aged_out         INTEGER DEFAULT 0,
                river_visible    INTEGER DEFAULT 1,
                simhash_value    INTEGER DEFAULT 0,
                embedding_vector BLOB
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS source_affinity (
                source_id      TEXT PRIMARY KEY,
                affinity_score REAL DEFAULT 0.0,
                event_count    INTEGER DEFAULT 0,
                last_updated   INTEGER,
                velocity_tier  TEXT,
                slot_limit     INTEGER
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS interaction_events (
                id         TEXT PRIMARY KEY,
                source_id  TEXT NOT NULL,
                item_id    TEXT NOT NULL,
                event_type TEXT NOT NULL,
                timestamp  INTEGER NOT NULL,
                dwell_time REAL
            )
        """)

        // Indexes
        execute("CREATE INDEX IF NOT EXISTS idx_feed_items_source ON feed_items(source_id, fetched_at)")
        execute("CREATE INDEX IF NOT EXISTS idx_feed_items_river ON feed_items(river_visible, relevance_score)")
        execute("CREATE INDEX IF NOT EXISTS idx_events_source ON interaction_events(source_id, timestamp)")
    }

    // MARK: - Feed Items: Write

    /// Inserts or replaces a batch of FeedItems.
    func upsertFeedItems(_ items: [FeedItem]) {
        queue.sync {
            execute("BEGIN TRANSACTION")
            let sql = """
                INSERT OR REPLACE INTO feed_items
                (id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                 cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                 simhash_value, embedding_vector)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                execute("ROLLBACK")
                return
            }
            defer { sqlite3_finalize(stmt) }

            for item in items {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                bindText(stmt, 1, item.id.uuidString)
                bindText(stmt, 2, item.sourceID.uuidString)
                bindText(stmt, 3, item.title)
                bindText(stmt, 4, item.link.absoluteString)
                sqlite3_bind_int64(stmt, 5, Int64(item.publishedAt.timeIntervalSince1970))
                sqlite3_bind_int64(stmt, 6, Int64(item.fetchedAt.timeIntervalSince1970))
                bindText(stmt, 7, item.excerpt)
                bindOptionalText(stmt, 8, item.imageURL)
                bindOptionalText(stmt, 9, item.author)
                bindOptionalText(stmt, 10, item.clusterID?.uuidString)
                sqlite3_bind_int(stmt, 11, item.isCanonical ? 1 : 0)
                bindText(stmt, 12, item.velocityTier.rawValue)
                sqlite3_bind_double(stmt, 13, item.relevanceScore)
                sqlite3_bind_int(stmt, 14, item.agedOut ? 1 : 0)
                sqlite3_bind_int(stmt, 15, item.riverVisible ? 1 : 0)
                sqlite3_bind_int64(stmt, 16, Int64(bitPattern: item.simhashValue))
                // embedding_vector: nil for Phase 2a
                sqlite3_bind_null(stmt, 17)

                sqlite3_step(stmt)
            }
            execute("COMMIT")
        }
    }

    /// Updates the relevance score and aged_out flag for a batch of items.
    func updateScores(_ updates: [(id: UUID, relevanceScore: Double, agedOut: Bool)]) {
        queue.sync {
            execute("BEGIN TRANSACTION")
            let sql = "UPDATE feed_items SET relevance_score = ?, aged_out = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                execute("ROLLBACK")
                return
            }
            defer { sqlite3_finalize(stmt) }

            for update in updates {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_double(stmt, 1, update.relevanceScore)
                sqlite3_bind_int(stmt, 2, update.agedOut ? 1 : 0)
                bindText(stmt, 3, update.id.uuidString)
                sqlite3_step(stmt)
            }
            execute("COMMIT")
        }
    }

    // MARK: - Feed Items: Read

    /// Fetches all river-visible items (not aged out), ordered by relevance descending.
    func fetchRiverItems() -> [FeedItem] {
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE river_visible = 1 AND aged_out = 0
            ORDER BY relevance_score DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Fetches river-visible items within the retention window, including aged-out ones.
    /// Respects rate-gating (river_visible = 1) but does NOT filter by aged_out,
    /// so the Today feed can scroll through the full 30-day history with decay opacity.
    func fetchRiverItemsAllHistory(days: Int = CachePolicy.cacheRetentionDays) -> [FeedItem] {
        let cutoff = Int64(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE river_visible = 1 AND published_at >= ?
            ORDER BY relevance_score DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoff)

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Fetches all items within the retention window regardless of river_visible / aged_out flags.
    /// Used to populate the source/folder views with the full 30-day cache.
    func fetchAllRecentItems(days: Int = CachePolicy.cacheRetentionDays) -> [FeedItem] {
        let cutoff = Int64(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE published_at >= ?
            ORDER BY published_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoff)

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Fetches all items (including aged-out) for a given source, for frequency analysis.
    func fetchItems(forSource sourceID: UUID) -> [FeedItem] {
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE source_id = ?
            ORDER BY published_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sourceID.uuidString)

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Checks whether an item with the given ID already exists.
    func itemExists(id: UUID) -> Bool {
        let sql = "SELECT 1 FROM feed_items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Returns the set of existing item IDs from a given candidate set.
    func existingItemIDs(from candidates: Set<UUID>) -> Set<UUID> {
        guard !candidates.isEmpty else { return [] }
        // For small sets, query individually. For large sets, use IN clause.
        var existing = Set<UUID>()
        let sql = "SELECT 1 FROM feed_items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for candidate in candidates {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bindText(stmt, 1, candidate.uuidString)
            if sqlite3_step(stmt) == SQLITE_ROW {
                existing.insert(candidate)
            }
        }
        return existing
    }

    /// Fetches all non-aged-out items for scoring.
    func fetchAllActiveItems() -> [FeedItem] {
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE aged_out = 0
            ORDER BY published_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    // MARK: - Clustering (Phase 2b)

    /// Fetches items published within the given time window, not aged out.
    func fetchRecentItems(since cutoff: Date) -> [FeedItem] {
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE aged_out = 0 AND published_at >= ?
            ORDER BY published_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cutoff.timeIntervalSince1970))

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Clears cluster_id and is_canonical for items older than the given cutoff.
    func clearClusterFields(olderThan cutoff: Date) {
        queue.sync {
            let sql = "UPDATE feed_items SET cluster_id = NULL, is_canonical = 0 WHERE published_at < ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(cutoff.timeIntervalSince1970))
            sqlite3_step(stmt)
        }
    }

    /// Updates cluster_id and is_canonical for a batch of items.
    func updateClusterAssignments(_ updates: [(id: UUID, clusterID: UUID, isCanonical: Bool)]) {
        queue.sync {
            execute("BEGIN TRANSACTION")
            let sql = "UPDATE feed_items SET cluster_id = ?, is_canonical = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                execute("ROLLBACK")
                return
            } 
            defer { sqlite3_finalize(stmt) }

            for update in updates {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bindText(stmt, 1, update.clusterID.uuidString)
                sqlite3_bind_int(stmt, 2, update.isCanonical ? 1 : 0)
                bindText(stmt, 3, update.id.uuidString)
                sqlite3_step(stmt)
            }
            execute("COMMIT")
        }
    }

    /// Updates the embedding vector for a single item.
    func updateEmbeddingVector(itemID: UUID, vector: [Float]) {
        queue.sync {
            let sql = "UPDATE feed_items SET embedding_vector = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            // Serialize [Float] to BLOB
            let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            data.withUnsafeBytes { rawBuffer in
                sqlite3_bind_blob(stmt, 1, rawBuffer.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                bindText(stmt, 2, itemID.uuidString)
                sqlite3_step(stmt)
            }
        }
    }

    /// Fetches all items belonging to a given cluster.
    func fetchItems(forCluster clusterID: UUID) -> [FeedItem] {
        let sql = """
            SELECT id, source_id, title, link, published_at, fetched_at, excerpt, image_url, author,
                   cluster_id, is_canonical, velocity_tier, relevance_score, aged_out, river_visible,
                   simhash_value
            FROM feed_items
            WHERE cluster_id = ?
            ORDER BY published_at ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, clusterID.uuidString)

        var items: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = feedItem(from: stmt) {
                items.append(item)
            }
        }
        return items
    }

    /// Clears stale embedding vectors for items outside the cluster window.
    func clearStaleEmbeddings(olderThan cutoff: Date) {
        queue.sync {
            let sql = "UPDATE feed_items SET embedding_vector = NULL WHERE published_at < ? AND embedding_vector IS NOT NULL"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(cutoff.timeIntervalSince1970))
            sqlite3_step(stmt)
        }
    }

    // MARK: - Source Affinity

    /// Upserts a source affinity record.
    func upsertAffinity(_ record: SourceAffinityRecord) {
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO source_affinity
                (source_id, affinity_score, event_count, last_updated, velocity_tier, slot_limit)
                VALUES (?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, record.sourceID.uuidString)
            sqlite3_bind_double(stmt, 2, record.affinityScore)
            sqlite3_bind_int64(stmt, 3, Int64(record.eventCount))
            sqlite3_bind_int64(stmt, 4, Int64(record.lastUpdated.timeIntervalSince1970))
            bindText(stmt, 5, record.velocityTier.rawValue)
            sqlite3_bind_int64(stmt, 6, Int64(clamping: record.slotLimit))
            sqlite3_step(stmt)
        }
    }

    /// Fetches the affinity record for a source, or nil if none exists.
    func fetchAffinity(forSource sourceID: UUID) -> SourceAffinityRecord? {
        let sql = "SELECT * FROM source_affinity WHERE source_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sourceID.uuidString)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return affinityRecord(from: stmt)
    }

    /// Fetches all source affinity records.
    func fetchAllAffinities() -> [SourceAffinityRecord] {
        let sql = "SELECT * FROM source_affinity ORDER BY affinity_score DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var records: [SourceAffinityRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = affinityRecord(from: stmt) {
                records.append(record)
            }
        }
        return records
    }

    // MARK: - Interaction Events

    /// Inserts an interaction event.
    func insertEvent(_ event: InteractionEvent) {
        queue.sync {
            let sql = """
                INSERT OR IGNORE INTO interaction_events
                (id, source_id, item_id, event_type, timestamp, dwell_time)
                VALUES (?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, event.id.uuidString)
            bindText(stmt, 2, event.sourceID.uuidString)
            bindText(stmt, 3, event.itemID.uuidString)
            bindText(stmt, 4, event.eventType.rawValue)
            sqlite3_bind_int64(stmt, 5, Int64(event.timestamp.timeIntervalSince1970))
            if let dwell = event.dwellTime {
                sqlite3_bind_double(stmt, 6, dwell)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
        }
    }

    // MARK: - Affinity Reset (Phase 2d)

    /// Resets the affinity score for a single source to 0.0 and clears its event count.
    func resetAffinity(forSource sourceID: UUID) {
        queue.sync {
            let sql = """
                UPDATE source_affinity
                SET affinity_score = 0.0, event_count = 0, last_updated = ?
                WHERE source_id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
            bindText(stmt, 2, sourceID.uuidString)
            sqlite3_step(stmt)
        }
    }

    /// Clears all affinity data: resets source_affinity and deletes all interaction_events.
    func resetAllAffinityData() {
        queue.sync {
            execute("DELETE FROM interaction_events")
            execute("UPDATE source_affinity SET affinity_score = 0.0, event_count = 0, last_updated = \(Int64(Date().timeIntervalSince1970))")
        }
    }

    // MARK: - Rate Gating (Phase 2c)

    /// Counts river-visible items per source for the current calendar day.
    ///
    /// - Returns: Dictionary mapping source UUID to visible item count today.
    func countVisibleItemsPerSourceToday() -> [UUID: Int] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let sql = """
            SELECT source_id, COUNT(*) FROM feed_items
            WHERE river_visible = 1 AND aged_out = 0 AND fetched_at >= ?
            GROUP BY source_id
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(startOfDay.timeIntervalSince1970))

        var counts: [UUID: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idStr = columnText(stmt, 0), let uuid = UUID(uuidString: idStr) {
                counts[uuid] = Int(sqlite3_column_int(stmt, 1))
            }
        }
        return counts
    }

    /// Returns historical item counts per 2-hour window for flood detection.
    ///
    /// Divides the lookback period into 2-hour windows and counts items per window.
    /// Used to compute mean + sigma for flood threshold.
    ///
    /// - Parameters:
    ///   - sourceID: The source to analyze.
    ///   - windowHours: Size of each time window in hours (default 2).
    ///   - lookbackDays: Number of days to look back (default 7).
    /// - Returns: Array of item counts, one per window.
    func fetchHistoricalItemCounts(forSource sourceID: UUID, windowHours: Int = 2, lookbackDays: Int = 7) -> [Int] {
        let now = Date()
        let lookbackStart = now.addingTimeInterval(-Double(lookbackDays) * 86400)
        let windowSeconds = Double(windowHours) * 3600

        // Fetch all items for this source in the lookback period
        let sql = """
            SELECT published_at FROM feed_items
            WHERE source_id = ? AND published_at >= ?
            ORDER BY published_at ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sourceID.uuidString)
        sqlite3_bind_int64(stmt, 2, Int64(lookbackStart.timeIntervalSince1970))

        var timestamps: [TimeInterval] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            timestamps.append(TimeInterval(sqlite3_column_int64(stmt, 0)))
        }

        guard !timestamps.isEmpty else { return [] }

        // Bucket timestamps into windows
        let startTime = lookbackStart.timeIntervalSince1970
        let endTime = now.timeIntervalSince1970
        let windowCount = Int(ceil((endTime - startTime) / windowSeconds))

        var counts = [Int](repeating: 0, count: windowCount)
        for ts in timestamps {
            let windowIndex = Int((ts - startTime) / windowSeconds)
            if windowIndex >= 0 && windowIndex < windowCount {
                counts[windowIndex] += 1
            }
        }

        // Only return non-zero windows (exclude the current window to avoid bias)
        let nonCurrentWindows = counts.dropLast()
        return Array(nonCurrentWindows)
    }

    /// Sets river_visible for a batch of item IDs.
    func setRiverVisible(_ visible: Bool, forItemIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            execute("BEGIN TRANSACTION")
            let sql = "UPDATE feed_items SET river_visible = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else {
                execute("ROLLBACK")
                return
            }
            defer { sqlite3_finalize(stmt) }

            let visibleInt: Int32 = visible ? 1 : 0
            for id in ids {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int(stmt, 1, visibleInt)
                bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            execute("COMMIT")
        }
    }

    // MARK: - Maintenance

    /// Deletes items that have been aged out for more than `days` days.
    func purgeAgedItems(olderThan days: Int = 30) {
        queue.sync {
            let cutoff = Int64(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
            let sql = "DELETE FROM feed_items WHERE aged_out = 1 AND fetched_at < ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, cutoff)
            sqlite3_step(stmt)
        }
    }

    /// Returns the total count of items in the database.
    func totalItemCount() -> Int {
        let sql = "SELECT COUNT(*) FROM feed_items"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.pointer, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Row Parsing

    private func feedItem(from stmt: OpaquePointer?) -> FeedItem? {
        guard let stmt else { return nil }
        guard let idStr = columnText(stmt, 0),
              let id = UUID(uuidString: idStr),
              let sourceIDStr = columnText(stmt, 1),
              let sourceID = UUID(uuidString: sourceIDStr),
              let title = columnText(stmt, 2),
              let linkStr = columnText(stmt, 3),
              let link = URL(string: linkStr)
        else { return nil }

        let publishedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
        let fetchedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))
        let excerpt = columnText(stmt, 6) ?? ""
        let imageURL = columnText(stmt, 7)
        let author = columnText(stmt, 8)
        let clusterID = columnText(stmt, 9).flatMap { UUID(uuidString: $0) }
        let isCanonical = sqlite3_column_int(stmt, 10) != 0
        let tierStr = columnText(stmt, 11) ?? "article"
        let velocityTier = VelocityTier(rawValue: tierStr) ?? .article
        let relevanceScore = sqlite3_column_double(stmt, 12)
        let agedOut = sqlite3_column_int(stmt, 13) != 0
        let riverVisible = sqlite3_column_int(stmt, 14) != 0
        let simhash = UInt64(bitPattern: sqlite3_column_int64(stmt, 15))

        return FeedItem(
            id: id,
            sourceID: sourceID,
            title: title,
            link: link,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            excerpt: excerpt,
            imageURL: imageURL,
            author: author,
            clusterID: clusterID,
            isCanonical: isCanonical,
            velocityTier: velocityTier,
            relevanceScore: relevanceScore,
            agedOut: agedOut,
            riverVisible: riverVisible,
            simhashValue: simhash
        )
    }

    private func affinityRecord(from stmt: OpaquePointer?) -> SourceAffinityRecord? {
        guard let stmt else { return nil }
        guard let sourceIDStr = columnText(stmt, 0),
              let sourceID = UUID(uuidString: sourceIDStr)
        else { return nil }

        let affinityScore = sqlite3_column_double(stmt, 1)
        let eventCount = Int(sqlite3_column_int(stmt, 2))
        let lastUpdated = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
        let tierStr = columnText(stmt, 4) ?? "article"
        let velocityTier = VelocityTier(rawValue: tierStr) ?? .article
        let slotLimit = Int(sqlite3_column_int(stmt, 5))

        return SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: affinityScore,
            eventCount: eventCount,
            lastUpdated: lastUpdated,
            velocityTier: velocityTier,
            slotLimit: slotLimit
        )
    }

    // MARK: - SQLite Helpers

    private func execute(_ sql: String) {
        sqlite3_exec(db.pointer, sql, nil, nil, nil)
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}

// MARK: - DatabaseHandle (Sendable wrapper)

/// Thread-safe wrapper so `SQLiteStore` can be `Sendable`.
/// All access is serialized through the store's dispatch queue.
private final class DatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }
}
