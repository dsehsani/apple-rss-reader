//
//  FeedID.swift
//  Payam
//
//  Swift port of payam-polling/src/lib/keys.mjs. Lets the iOS client compute
//  the same `feedId` string the server uses to key the `userFeeds` and
//  `items` DynamoDB tables, so cloud-delivered rows can be mapped back to
//  the local `Source` they belong to.
//

import CryptoKit
import Foundation

enum FeedID {

    /// Canonicalizes a feed URL exactly the way `canonicalizeFeedUrl` does in
    /// keys.mjs: rewrite leading `http://` → `https://` at the string level
    /// (before URL parsing), then lowercase the scheme + host, preserving
    /// path/query case because some feeds care.
    static func canonicalize(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") {
            trimmed = "https://" + trimmed.dropFirst("http://".count)
        }

        guard var comps = URLComponents(string: trimmed) else { return trimmed }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        return comps.url?.absoluteString ?? trimmed
    }

    /// Returns the same 32-char hex identifier the server stores in `feedId`.
    static func id(for feedURL: String) -> String {
        let canon = canonicalize(feedURL)
        let digest = SHA256.hash(data: Data(canon.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }
}
