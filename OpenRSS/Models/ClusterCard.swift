//
//  ClusterCard.swift
//  OpenRSS
//
//  Phase 2b — Model for a clustered story card.
//  Groups multiple FeedItems covering the same story into
//  a single visual unit for the River feed.
//

import Foundation

// MARK: - ClusterCard

struct ClusterCard: Identifiable, Hashable, Sendable {
    let id: UUID
    let canonicalItem: FeedItem
    let sourceCount: Int
    let sourceNames: [String]
    let allItemIDs: [UUID]

    /// All FeedItems in this cluster (including the canonical item).
    /// Used by ClusterCardView to render tappable article rows on expand.
    let allItems: [FeedItem]

    init(
        id: UUID = UUID(),
        canonicalItem: FeedItem,
        sourceCount: Int,
        sourceNames: [String],
        allItemIDs: [UUID],
        allItems: [FeedItem] = []
    ) {
        self.id = id
        self.canonicalItem = canonicalItem
        self.sourceCount = sourceCount
        self.sourceNames = sourceNames
        self.allItemIDs = allItemIDs
        self.allItems = allItems
    }
}
