//
//  ArticleState.swift
//  OpenRSS
//
//  SwiftData model for synced per-article read/bookmark/paywall state.
//  Keyed by SHA-256 hash of the article URL for stable cross-device identity.
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class ArticleState {

    // MARK: - Persisted Properties

    /// SHA-256 hash of `articleURL` (hex string).
    /// Used as the stable cross-device key — UUIDs differ per device.
    @Attribute(.unique) var articleURLHash: String

    /// The original article URL. Stored for debugging and de-duplication.
    var articleURL: String

    /// Monotonic: once true on any device, never reverted by sync.
    var isRead: Bool = false

    /// Timestamp-based conflict resolution — most recent write wins.
    var isBookmarked: Bool = false

    /// Manually flagged as paywalled by the user.
    var isPaywalled: Bool = false

    /// Updated on every write. Used to resolve bookmark conflicts.
    var lastModifiedAt: Date

    // MARK: - Initialization

    init(articleURL: String) {
        self.articleURL = articleURL
        self.articleURLHash = ArticleState.hash(articleURL)
        self.lastModifiedAt = Date()
    }

    // MARK: - Hash Helper

    static func hash(_ url: String) -> String {
        let data = Data(url.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
