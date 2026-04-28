//
//  InteractionEvent.swift
//  OpenRSS
//
//  Phase 2a — Model for tracking user interactions with feed items.
//  Used by the affinity system (Phase 2d) to compute per-source scores.
//

import Foundation

// MARK: - InteractionEventType

enum InteractionEventType: String, Codable, Sendable {
    // Tier 1 — strong positive
    case articleOpen
    case sourceBrowse
    case digestExpand
    case clusterExpand
    case articleShare

    // Tier 2 — medium positive
    case dwellLong
    case dwellMedium
    case scrollSlow
    case returnVisit

    // Tier 3 — negative
    case quickBounce
    case scrollFastPast
    case explicitDismiss

    /// Weight used in the EMA affinity update.
    var weight: Double {
        switch self {
        case .sourceBrowse:    return  1.2
        case .articleShare:    return  1.1
        case .articleOpen:     return  1.0
        case .returnVisit:     return  0.9
        case .digestExpand:    return  0.8
        case .dwellLong:       return  0.7
        case .clusterExpand:   return  0.6
        case .dwellMedium:     return  0.4
        case .scrollSlow:      return  0.2
        case .explicitDismiss: return -0.5
        case .quickBounce:     return -0.3
        case .scrollFastPast:  return -0.1
        }
    }
}

// MARK: - InteractionEvent

struct InteractionEvent: Identifiable, Sendable {
    let id: UUID
    let sourceID: UUID
    let itemID: UUID
    let eventType: InteractionEventType
    let timestamp: Date
    let dwellTime: TimeInterval?

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        itemID: UUID,
        eventType: InteractionEventType,
        timestamp: Date = Date(),
        dwellTime: TimeInterval? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.itemID = itemID
        self.eventType = eventType
        self.timestamp = timestamp
        self.dwellTime = dwellTime
    }
}
