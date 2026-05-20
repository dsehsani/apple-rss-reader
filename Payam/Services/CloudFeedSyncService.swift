//
//  CloudFeedSyncService.swift
//  Payam
//
//  Fetches feed item deltas from the Payam cloud for premium users.
//  Returns [FeedItem] in the same format as FeedIngestService so the
//  downstream pipeline (clustering, gating, decay, snapshot) is unchanged.
//

import Foundation

final class CloudFeedSyncService: Sendable {

    static let shared = CloudFeedSyncService()

    private let store = SQLiteStore.shared

    // MARK: - Sync Token

    private static let syncTokenKey = "payam.cloud.syncToken"

    private var lastSyncToken: String? {
        get { UserDefaults.standard.string(forKey: Self.syncTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncTokenKey) }
    }

    // MARK: - Response Types

    private struct RiverResponse: Decodable {
        let items: [CloudFeedItem]
        let syncToken: String?
        let hasMore: Bool?
    }

    private struct CloudFeedItem: Decodable {
        let id: String
        let sourceID: String
        let title: String
        let link: String
        let publishedAt: TimeInterval
        let fetchedAt: TimeInterval
        let excerpt: String?
        let imageURL: String?
        let audioURL: String?
        let videoURL: String?
        let author: String?
        let velocityTier: String?
        let isRead: Bool?
        let isBookmarked: Bool?
    }

    // MARK: - Sync

    /// Fetches new items from the cloud since the last sync.
    /// Returns FeedItem array compatible with the local pipeline.
    func sync() async -> [FeedItem] {
        let since = lastSyncToken ?? "0"
        let path = "/v1/river?since=\(since)&limit=500"

        do {
            let response = try await PayamAPIClient.send(
                RiverResponse.self,
                path: path
            )

            let feedItems = response.items.compactMap { convertToFeedItem($0) }

            if !feedItems.isEmpty {
                store.upsertFeedItems(feedItems)
                print("☁️ Cloud sync: \(feedItems.count) items")
            }

            if let token = response.syncToken {
                UserDefaults.standard.set(token, forKey: Self.syncTokenKey)
            }

            return feedItems
        } catch {
            print("☁️ Cloud sync failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Conversion

    private func convertToFeedItem(_ cloud: CloudFeedItem) -> FeedItem? {
        guard let id = UUID(uuidString: cloud.id),
              let sourceID = UUID(uuidString: cloud.sourceID),
              let link = URL(string: cloud.link)
        else { return nil }

        let tier = cloud.velocityTier.flatMap { VelocityTier(rawValue: $0) } ?? .article

        return FeedItem(
            id: id,
            sourceID: sourceID,
            title: cloud.title,
            link: link,
            publishedAt: Date(timeIntervalSince1970: cloud.publishedAt),
            fetchedAt: Date(timeIntervalSince1970: cloud.fetchedAt),
            excerpt: cloud.excerpt ?? "",
            imageURL: cloud.imageURL,
            audioURL: cloud.audioURL,
            videoURL: cloud.videoURL,
            author: cloud.author,
            velocityTier: tier,
            simhashValue: SimHash.compute(cloud.title)
        )
    }

    // MARK: - Reset

    func clearSyncToken() {
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
    }
}
