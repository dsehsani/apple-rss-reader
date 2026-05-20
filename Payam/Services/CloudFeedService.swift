//
//  CloudFeedService.swift
//  Payam
//
//  Fire-and-forget cloud subscription sync. When a user subscribes or
//  unsubscribes locally, this notifies the server so subscriber_count
//  updates and the polling/pre-extraction pipeline responds.
//

import Foundation

enum CloudFeedService {

    /// Notifies the server that the user subscribed to a feed.
    static func syncAdded(feedURL: String) async {
        await syncFeeds(added: [feedURL], removed: [])
    }

    /// Notifies the server that the user unsubscribed from a feed.
    static func syncRemoved(feedURL: String) async {
        await syncFeeds(added: [], removed: [feedURL])
    }

    /// Batch sync — used during OPML import or bulk operations.
    static func syncBatch(added: [String], removed: [String]) async {
        await syncFeeds(added: added, removed: removed)
    }

    // MARK: - Private

    private struct FeedSyncBody: Encodable {
        let added: [String]
        let removed: [String]
    }

    private static func syncFeeds(added: [String], removed: [String]) async {
        guard CloudAuthService.hasValidToken else { return }

        do {
            try await PayamAPIClient.sendNoContent(
                path: "/v1/feeds",
                body: FeedSyncBody(added: added, removed: removed)
            )
        } catch {
            // Non-critical — local subscription is the source of truth.
            print("⚠️ Cloud feed sync failed: \(error.localizedDescription)")
        }
    }
}
