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

    /// Timestamp when the user subscribed.
    var addedAt: Date

    /// The folder this feed belongs to. `nil` means the feed is "unfiled".
    var folder: FolderModel?

    // MARK: - Initialization

    init(
        feedURL: String,
        title: String,
        websiteURL: String = "",
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.feedURL = feedURL
        self.title = title.isEmpty ? feedURL : title
        self.websiteURL = websiteURL.isEmpty ? feedURL : websiteURL
        self.isEnabled = isEnabled
        self.addedAt = Date()
    }
}
