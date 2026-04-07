//
//  FeedModel.swift
//  OpenRSS
//
//  SwiftData persistent model representing a user-subscribed RSS feed.
//  Maps to the `Source` domain model.
//

import Foundation
import SwiftData

/// A persisted RSS feed subscription belonging to a user-created folder.
@Model
final class FeedModel {

    // MARK: - Persisted Properties

    /// Stable unique identifier — also used as `Source.id` when mapping.
    var id: UUID

    /// The RSS/Atom/JSON feed URL entered by the user.
    var feedURL: String

    /// Display name auto-fetched from the feed's channel title
    /// (e.g. "TechCrunch"). Editable by the user.
    var title: String

    /// The feed's home website URL (derived from the feed URL host).
    var websiteURL: String

    /// When false, this feed is skipped during refresh. Toggled via swipe action.
    var isEnabled: Bool

    /// When true, all articles from this feed are treated as paywalled.
    /// Set manually by the user as a fallback when automatic detection misses.
    var isPaywalled: Bool

    /// Timestamp when the user subscribed.
    var addedAt: Date

    /// Raw storage for auto-inferred posting frequency tier (SwiftData can't persist custom enums directly).
    var velocityTierRaw: String

    /// Raw storage for user decay override. Empty string means nil (auto).
    var decayOverrideRaw: String

    /// The folder this feed belongs to. `nil` means the feed is "unfiled".
    var folder: FolderModel?

    // MARK: - Computed Wrappers

    /// Auto-inferred posting frequency tier, used to determine decay half-life.
    @Transient
    var velocityTier: VelocityTier {
        get { VelocityTier(rawValue: velocityTierRaw) ?? .daily }
        set { velocityTierRaw = newValue.rawValue }
    }

    /// User override for decay rate. When non-nil, takes priority over the auto-inferred tier.
    @Transient
    var decayOverride: VelocityTier? {
        get { decayOverrideRaw.isEmpty ? nil : VelocityTier(rawValue: decayOverrideRaw) }
        set { decayOverrideRaw = newValue?.rawValue ?? "" }
    }

    // MARK: - Initialization

    init(
        feedURL: String,
        title: String,
        websiteURL: String = "",
        isEnabled: Bool = true,
        isPaywalled: Bool = false
    ) {
        self.id = UUID()
        self.feedURL = feedURL
        self.title = title.isEmpty ? feedURL : title
        self.websiteURL = websiteURL.isEmpty ? feedURL : websiteURL
        self.isEnabled = isEnabled
        self.isPaywalled = isPaywalled
        self.addedAt = Date()
        self.velocityTierRaw = VelocityTier.daily.rawValue
        self.decayOverrideRaw = ""
    }
}
