//
//  CloudFeedSubscriptionService.swift
//  Payam
//
//  Mirrors the user's local feed subscriptions to the polling server's
//  POST /v1/feeds endpoint. Without this, the server has no record of
//  which feeds to poll for this device → GET /v1/river returns empty →
//  the iOS River shows stale articles indefinitely.
//
//  The sync is idempotent: it compares the current canonical-feedURL set
//  against the last-pushed snapshot in UserDefaults and only sends the
//  delta. Failures don't poison the snapshot, so a transient network
//  blip just re-pushes on the next call. Calls are debounced so an OPML
//  import of N feeds settles into a single POST.
//

import Foundation
import os

private let log = Logger(subsystem: "com.openrss", category: "SubscriptionSync")

final class CloudFeedSubscriptionService: @unchecked Sendable {

    static let shared = CloudFeedSubscriptionService()

    /// Snapshot of canonical feed URLs the server has acknowledged. Stored as
    /// a plain `[String]` in UserDefaults — small (<1KB for typical users),
    /// no need for a separate file.
    private static let lastPushedKey = "payam.subscriptionSync.lastPushedFeeds"

    private let lock = NSLock()
    private var debounceTask: Task<Void, Never>?

    private init() {}

    /// Schedules a reconcile against the server. Coalesces rapid calls — an
    /// OPML import that inserts 100 feeds triggers one POST, not 100.
    func requestSync(debounceMillis: UInt64 = 1_000) {
        lock.lock()
        defer { lock.unlock() }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceMillis * 1_000_000)
            if Task.isCancelled { return }
            await self?.reconcile()
        }
    }

    /// Diffs the current Source list against the last-pushed snapshot and
    /// POSTs only the changes. No-op when the set is unchanged.
    private func reconcile() async {
        let snapshot = await collectSnapshot()

        let current = Set(snapshot.map { $0.canonical })
        let lastPushed = Set(UserDefaults.standard.stringArray(forKey: Self.lastPushedKey) ?? [])

        let added = current.subtracting(lastPushed)
        let removed = lastPushed.subtracting(current)

        if added.isEmpty && removed.isEmpty { return }

        var folderByCanonical: [String: String?] = [:]
        for s in snapshot { folderByCanonical[s.canonical] = s.folder }

        let body = FeedsRequest(
            added: added.map { canonical in
                FeedsRequest.Added(feedUrl: canonical, folder: folderByCanonical[canonical] ?? nil)
            },
            removed: removed.map { FeedsRequest.Removed(feedUrl: $0) }
        )

        let url = CloudHTTP.pollingBase.appendingPathComponent("v1/feeds")
        do {
            let (resp, _) = try await CloudHTTP.post(url, body: body, as: FeedsResponse.self)
            log.info("Pushed added=\(added.count, privacy: .public) removed=\(removed.count, privacy: .public) — server applied added=\(resp.added, privacy: .public) removed=\(resp.removed, privacy: .public)")
            UserDefaults.standard.set(Array(current), forKey: Self.lastPushedKey)
        } catch {
            log.error("Reconcile failed: \(String(describing: error), privacy: .public)")
        }
    }

    private struct SourceSnapshot {
        let canonical: String
        let folder: String?
    }

    @MainActor
    private func collectSnapshot() -> [SourceSnapshot] {
        let svc = SwiftDataService.shared
        let folderByID = Dictionary(uniqueKeysWithValues: svc.categories.map { ($0.id, $0.name) })
        return svc.sources.map {
            SourceSnapshot(
                canonical: FeedID.canonicalize($0.feedURL),
                folder: folderByID[$0.categoryID]
            )
        }
    }
}

// MARK: - Wire types

private struct FeedsRequest: Encodable {
    struct Added: Encodable {
        let feedUrl: String
        let folder: String?
    }
    struct Removed: Encodable {
        let feedUrl: String
    }
    let added: [Added]
    let removed: [Removed]
}

private struct FeedsResponse: Decodable {
    let added: Int
    let removed: Int
}
