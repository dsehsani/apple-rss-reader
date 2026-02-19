//
//  SourcesViewModel.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Sources management tab
@Observable
final class SourcesViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService

    // MARK: - Published State

    var expandedCategories: Set<UUID> = []
    var searchText: String = ""
    var showingAddSourceSheet: Bool = false
    var showingManageCategoriesSheet: Bool = false

    // MARK: - Computed Properties

    /// All categories sorted by order
    var categories: [Category] {
        dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Filtered categories based on search text
    var filteredCategories: [Category] {
        guard !searchText.isEmpty else { return categories }

        let query = searchText.lowercased()
        return categories.filter { category in
            // Match category name
            if category.name.lowercased().contains(query) {
                return true
            }
            // Match any source name within the category
            return sources(for: category).contains {
                $0.name.lowercased().contains(query)
            }
        }
    }

    /// Get sources for a specific category
    func sources(for category: Category) -> [Source] {
        dataService.sources
            .filter { $0.categoryID == category.id }
            .sorted { $0.name < $1.name }
    }

    /// Filtered sources for a category based on search text
    func filteredSources(for category: Category) -> [Source] {
        let allSources = sources(for: category)
        guard !searchText.isEmpty else { return allSources }

        let query = searchText.lowercased()
        return allSources.filter { $0.name.lowercased().contains(query) }
    }

    /// Get source count for a category
    func sourceCount(for category: Category) -> Int {
        sources(for: category).count
    }

    /// Get unread count for a category
    func unreadCount(for category: Category) -> Int {
        dataService.unreadCountForCategory(category.id)
    }

    /// Get unread count for a source
    func unreadCount(for source: Source) -> Int {
        dataService.unreadCountForSource(source.id)
    }

    /// Check if a category is expanded
    func isExpanded(_ category: Category) -> Bool {
        expandedCategories.contains(category.id)
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = SwiftDataService.shared) {
        self.dataService = dataService
    }

    // MARK: - Actions

    /// Toggle category expansion
    func toggleExpansion(for category: Category) {
        withAnimation(Design.Animation.standard) {
            if expandedCategories.contains(category.id) {
                expandedCategories.remove(category.id)
            } else {
                expandedCategories.insert(category.id)
            }
        }
    }

    /// Expand all categories
    func expandAll() {
        withAnimation(Design.Animation.standard) {
            expandedCategories = Set(categories.map { $0.id })
        }
    }

    /// Collapse all categories
    func collapseAll() {
        withAnimation(Design.Animation.standard) {
            expandedCategories.removeAll()
        }
    }

    /// Show add source sheet
    func showAddSource() {
        showingAddSourceSheet = true
    }

    /// Show manage categories sheet
    func showManageCategories() {
        showingManageCategoriesSheet = true
    }

    /// Delete a source from SwiftData.
    func deleteSource(_ source: Source) {
        try? SwiftDataService.shared.deleteFeed(id: source.id)
    }

    /// Toggle a source's enabled state in SwiftData.
    func toggleSourceEnabled(_ source: Source) {
        try? SwiftDataService.shared.toggleFeedEnabled(id: source.id)
    }
}
