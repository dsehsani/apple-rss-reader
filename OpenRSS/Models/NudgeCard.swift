//
//  NudgeCard.swift
//  OpenRSS
//
//  Phase 2a — Model for a "nudge" card shown when a source floods the river
//  (e.g., a wire service publishing far above its normal baseline).
//

import Foundation

// MARK: - NudgeCard

struct NudgeCard: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceID: UUID
    let sourceName: String
    let itemCount: Int
    let message: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        sourceName: String,
        itemCount: Int,
        message: String = "",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.itemCount = itemCount
        self.message = message.isEmpty
            ? "\(sourceName) published \(itemCount) items recently"
            : message
        self.timestamp = timestamp
    }
}
