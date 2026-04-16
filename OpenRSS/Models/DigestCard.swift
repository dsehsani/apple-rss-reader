//
//  DigestCard.swift
//  OpenRSS
//
//  Phase 2c — Model for a digest card that bundles overflow articles
//  from a single source that exceed the daily slot limit.
//

import Foundation

// MARK: - DigestCard

struct DigestCard: Identifiable, Hashable, Sendable {
    let sourceID: UUID
    let sourceName: String
    let itemCount: Int
    let highlights: [String]       // 2-3 title snippets
    let overflowIDs: [UUID]
    let insertionPosition: Date

    /// Computed ID derived from the sourceID and insertion date for stable identity.
    var id: UUID {
        // Deterministic UUID from sourceID + day, so the same source on the same day
        // always produces the same digest card identity.
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: insertionPosition)
        let dayString = "\(sourceID.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        // Use a UUID v5-style deterministic hash
        var hasher = Hasher()
        hasher.combine(dayString)
        let hash = hasher.finalize()
        // Build a stable UUID from the hash bits
        let upper = UInt64(bitPattern: Int64(hash))
        let lower = UInt64(bitPattern: Int64(sourceID.hashValue))
        let uuid = UUID(uuid: (
            UInt8(truncatingIfNeeded: upper >> 56),
            UInt8(truncatingIfNeeded: upper >> 48),
            UInt8(truncatingIfNeeded: upper >> 40),
            UInt8(truncatingIfNeeded: upper >> 32),
            UInt8(truncatingIfNeeded: upper >> 24),
            UInt8(truncatingIfNeeded: upper >> 16),
            UInt8(truncatingIfNeeded: upper >> 8),
            UInt8(truncatingIfNeeded: upper),
            UInt8(truncatingIfNeeded: lower >> 56),
            UInt8(truncatingIfNeeded: lower >> 48),
            UInt8(truncatingIfNeeded: lower >> 40),
            UInt8(truncatingIfNeeded: lower >> 32),
            UInt8(truncatingIfNeeded: lower >> 24),
            UInt8(truncatingIfNeeded: lower >> 16),
            UInt8(truncatingIfNeeded: lower >> 8),
            UInt8(truncatingIfNeeded: lower)
        ))
        return uuid
    }

    init(
        sourceID: UUID,
        sourceName: String,
        itemCount: Int,
        highlights: [String],
        overflowIDs: [UUID],
        insertionPosition: Date
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.itemCount = itemCount
        self.highlights = highlights
        self.overflowIDs = overflowIDs
        self.insertionPosition = insertionPosition
    }
}
