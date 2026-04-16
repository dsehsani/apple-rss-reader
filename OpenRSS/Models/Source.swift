//
//  Source.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// Represents an RSS feed source
struct Source: Identifiable, Hashable {
    let id: UUID
    let name: String
    let feedURL: String
    let websiteURL: String
    let icon: String              // SF Symbol name (placeholder for favicon)
    let iconColor: Color          // Color for the icon background
    let categoryID: UUID
    var isEnabled: Bool           // Whether to fetch updates from this source
    var isPaywalled: Bool         // Whether the user has manually marked this feed as paywalled
    let addedAt: Date

    // Phase 2a — River pipeline fields
    /// Manual velocity tier override. When nil, the pipeline infers from publish frequency.
    var velocityTierOverride: VelocityTier?
    /// Effective daily slot limit for rate-gating. Derived from velocity tier if not set.
    var defaultSlotLimit: Int?

    // Phase 2 merge — Josh's fields
    /// Auto-inferred posting frequency for decay scoring.
    var velocityTier: VelocityTier
    /// User override for decay rate (overrides velocityTier when set).
    var decayOverride: VelocityTier?
    /// When true, clustered stories are down-weighted in the river.
    var preferUniqueStories: Bool
    /// Per-feed YouTube content-type filter.
    var hiddenYouTubeKinds: Set<YouTubeService.YouTubeContentKind>

    /// The effective tier used for decay scoring (override wins over auto-inferred).
    var effectiveVelocityTier: VelocityTier {
        decayOverride ?? velocityTierOverride ?? velocityTier
    }

    /// True if this source was added less than 14 days ago — decay is skipped.
    var isInGracePeriod: Bool {
        addedAt > Calendar.current.date(byAdding: .day, value: -14, to: Date())!
    }

    init(
        id: UUID = UUID(),
        name: String,
        feedURL: String,
        websiteURL: String = "",
        icon: String = "globe",
        iconColor: Color = .blue,
        categoryID: UUID,
        isEnabled: Bool = true,
        isPaywalled: Bool = false,
        addedAt: Date = Date(),
        velocityTierOverride: VelocityTier? = nil,
        defaultSlotLimit: Int? = nil,
        velocityTier: VelocityTier = .article,
        decayOverride: VelocityTier? = nil,
        preferUniqueStories: Bool = false,
        hiddenYouTubeKinds: Set<YouTubeService.YouTubeContentKind> = []
    ) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.websiteURL = websiteURL.isEmpty ? feedURL : websiteURL
        self.icon = icon
        self.iconColor = iconColor
        self.categoryID = categoryID
        self.isEnabled = isEnabled
        self.isPaywalled = isPaywalled
        self.addedAt = addedAt
        self.velocityTierOverride = velocityTierOverride
        self.defaultSlotLimit = defaultSlotLimit
        self.velocityTier = velocityTier
        self.decayOverride = decayOverride
        self.preferUniqueStories = preferUniqueStories
        self.hiddenYouTubeKinds = hiddenYouTubeKinds
    }
}

// MARK: - Hashable Conformance for Color

extension Source {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(feedURL)
        hasher.combine(categoryID)
    }

    static func == (lhs: Source, rhs: Source) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.feedURL == rhs.feedURL &&
        lhs.categoryID == rhs.categoryID
    }
}
