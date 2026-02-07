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
    let addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        feedURL: String,
        websiteURL: String = "",
        icon: String = "globe",
        iconColor: Color = .blue,
        categoryID: UUID,
        isEnabled: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.websiteURL = websiteURL.isEmpty ? feedURL : websiteURL
        self.icon = icon
        self.iconColor = iconColor
        self.categoryID = categoryID
        self.isEnabled = isEnabled
        self.addedAt = addedAt
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
