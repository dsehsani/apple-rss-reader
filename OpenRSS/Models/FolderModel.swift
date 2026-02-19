//
//  FolderModel.swift
//  OpenRSS
//
//  SwiftData persistent model representing a user-created folder
//  that groups RSS feeds. Maps to the `Category` domain model.
//

import Foundation
import SwiftData

/// A persisted folder that contains one or more RSS feeds.
/// Feeds within a folder share the same category in the Today feed.
@Model
final class FolderModel {

    // MARK: - Persisted Properties

    /// Stable unique identifier — also used as the `Category.id` when mapping.
    var id: UUID

    /// User-chosen display name (e.g. "Tech News", "Design").
    var name: String

    /// Controls the display order in My Feeds. Lower = shown first.
    var sortOrder: Int

    /// SF Symbol name for the folder icon (e.g. "folder.fill", "star.fill").
    var iconName: String = "folder.fill"

    /// Hex color string without `#` (e.g. "007AFF"). Drives the icon chip tint.
    var colorHex: String = "007AFF"

    /// Feeds belonging to this folder.
    /// Cascade delete: removing the folder removes all its feeds.
    @Relationship(deleteRule: .cascade, inverse: \FeedModel.folder)
    var feeds: [FeedModel] = []

    // MARK: - Initialization

    init(name: String, sortOrder: Int = 0, iconName: String = "folder.fill", colorHex: String = "007AFF") {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.iconName = iconName
        self.colorHex = colorHex
    }
}
