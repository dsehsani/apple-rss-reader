//
//  Category.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// Represents a category for organizing RSS feeds
struct Category: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String          // SF Symbol name
    let color: Color          // Accent color for the category
    let sortOrder: Int        // Display order in lists

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        color: Color = .blue,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
    }
}

// MARK: - Special Categories

extension Category {
    /// "All Updates" category - shows articles from all sources
    static let allUpdates = Category(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "All Updates",
        icon: "tray.full.fill",
        color: .blue,
        sortOrder: -1  // Always first
    )
}

// MARK: - Hashable Conformance for Color

extension Category {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(icon)
        hasher.combine(sortOrder)
    }

    static func == (lhs: Category, rhs: Category) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.icon == rhs.icon &&
        lhs.sortOrder == rhs.sortOrder
    }
}
