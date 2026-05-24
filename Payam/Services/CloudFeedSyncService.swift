//
//  CloudFeedSyncService.swift
//  Payam
//
//  Phase 2 — replaces direct RSS polling. Calls the deployed
//  GET /v1/river?since={epochSec} endpoint, maps the rows back to
//  `FeedItem`, persists them via `SQLiteStore.upsertFeedItems`, and stores
//  the server's reported `serverTime` so the next sync passes it as `since`.
//
//  TestFlight build: authentication is intentionally absent. The endpoint is
//  identified by an `x-payam-user` header carrying a per-install UUID stored
//  in Keychain. JWT auth lands in a follow-up phase; the server-side strip
//  has a matching `TODO(auth)` marker in payam-polling/src/river.mjs.
//

import Foundation
import os

private let log = Logger(subsystem: "com.openrss", category: "CloudSync")

// MARK: - Wire types

private struct RiverResponse: Decodable {
    let items: [RiverItemRow]
    let serverTime: Int
    // `state` and `deleted` are intentionally not modeled yet; ignored.
}

private struct RiverItemRow: Decodable {
    let feedId: String
    let link: String
    let itemId: String
    let title: String
    let excerpt: String?
    let author: String?
    let imageURL: String?
    let audioURL: String?
    let videoURL: String?
    let publishedAt: Int
    let fetchedAt: Int
}

// MARK: - CloudFeedSyncService

final class CloudFeedSyncService: Sendable {

    /// UserDefaults key tracking the last successful sync's `serverTime`. Reusing
    /// the existing `openrss.lastRiverRefresh` key would conflate "device clock
    /// at last refresh" with "server clock at last sync" — two unrelated values —
    /// so we keep this in a dedicated key.
    private static let lastServerTimeKey = "payam.cloudSync.lastServerTime"

    private let store: SQLiteStore

    init(store: SQLiteStore = .shared) {
        self.store = store
    }

    /// Calls /v1/river?since=…, maps the response into deduped `FeedItem`s,
    /// upserts them, and stores `serverTime` for the next call.
    ///
    /// Throws on network failure or non-2xx response. Callers (FeedIngestService
    /// → RiverPipeline → RiverViewModel) propagate the throw so the UI can
    /// surface a "couldn't reach server" banner instead of silently returning
    /// zero items.
    func sync(sources: [Source]) async throws -> [FeedItem] {
        // Map server `feedId` → local `Source` so cloud-delivered rows can be
        // attributed to the right subscription. Linear scan over ≤ ~100 sources.
        // If two local Sources canonicalize to the same feedURL (subscription
        // dupes), keep the last — `uniqueKeysWithValues` would crash here.
        let feedMap: [String: Source] = Dictionary(
            sources.map { (FeedID.id(for: $0.feedURL), $0) },
            uniquingKeysWith: { _, last in last }
        )

        let since = UserDefaults.standard.integer(forKey: Self.lastServerTimeKey)
        let url = Self.riverURL(since: since)

        let (response, _) = try await CloudHTTP.get(url, as: RiverResponse.self)

        // Map rows → FeedItem, dropping any whose feedId we don't recognize
        // locally (server has a subscription we haven't loaded yet).
        var unknownFeedIDs = Set<String>()
        let mapped: [FeedItem] = response.items.compactMap { row in
            guard let source = feedMap[row.feedId] else {
                unknownFeedIDs.insert(row.feedId)
                return nil
            }
            guard let id = UUID(uuidString: row.itemId),
                  let link = URL(string: row.link) else {
                return nil
            }
            return FeedItem(
                id: id,
                sourceID: source.id,
                title: row.title,
                link: link,
                publishedAt: Date(timeIntervalSince1970: TimeInterval(row.publishedAt)),
                fetchedAt: Date(timeIntervalSince1970: TimeInterval(row.fetchedAt)),
                excerpt: row.excerpt ?? "",
                imageURL: row.imageURL,
                audioURL: row.audioURL,
                videoURL: row.videoURL,
                author: row.author,
                velocityTier: source.effectiveVelocityTier,
                simhashValue: SimHash.compute(row.title)
            )
        }

        if !unknownFeedIDs.isEmpty {
            let sample = unknownFeedIDs.prefix(5).map { String($0.prefix(8)) }.joined(separator: ",")
            log.warning("Dropped \(unknownFeedIDs.count, privacy: .public) item(s) with unknown feedId — sample: \(sample, privacy: .public)")
            // No throw: a fully-empty `mapped` is legitimate during transients —
            // newly-added feeds aren't polled yet, CloudKit hasn't restored the
            // local Source list after reinstall, etc. With matching feedIdFor()
            // on both sides + the subscription push, a real format mismatch
            // can't recur. The OSLog warning is enough.
        }

        // Dedup against existing rows, then upsert.
        let candidateIDs = Set(mapped.map(\.id))
        let existingIDs = store.existingItemIDs(from: candidateIDs)
        let newItems = mapped.filter { !existingIDs.contains($0.id) }
        if !newItems.isEmpty {
            store.upsertFeedItems(newItems)
            log.info("Inserted \(newItems.count, privacy: .public) new items (serverTime=\(response.serverTime, privacy: .public))")
        }

        // Persist serverTime only after a successful upsert. Using the server's
        // clock — not Date() — avoids re-fetching the same window if the device
        // clock drifts.
        UserDefaults.standard.set(response.serverTime, forKey: Self.lastServerTimeKey)

        // Fire-and-forget hero pre-warm so river cards render with thumbnails.
        if !newItems.isEmpty {
            let inputs = newItems.map {
                HeroInput(pageURL: $0.link.absoluteString, imageURL: $0.imageURL)
            }
            Task.detached(priority: .utility) {
                await HeroPrefetcher.warm(inputs: inputs, budgetSeconds: 25)
            }
        }

        return newItems
    }

    // MARK: - URL building

    private static func riverURL(since: Int) -> URL {
        var comps = URLComponents(
            url: CloudHTTP.pollingBase.appendingPathComponent("v1/river"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "since", value: String(since))]
        return comps.url!
    }
}
