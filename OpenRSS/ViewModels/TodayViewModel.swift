//
//  TodayViewModel.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Today feed tab
@Observable
final class TodayViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService

    // MARK: - Published State

    var selectedCategory: Category?
    var articles: [Article] = []
    var isRefreshing: Bool = false
    var searchText: String = ""

    // MARK: - Computed Properties

    /// All categories including "All Updates"
    var allCategories: [Category] {
        [Category.allUpdates] + dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Filtered articles based on selected category and search text
    var filteredArticles: [Article] {
        var result = articles

        // Filter by category
        if let category = selectedCategory, category.id != Category.allUpdates.id {
            result = result.filter { $0.categoryID == category.id }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.excerpt.lowercased().contains(query)
            }
        }

        return result.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Unread count for a specific category
    func unreadCount(for category: Category) -> Int {
        if category.id == Category.allUpdates.id {
            return dataService.articles.filter { !$0.isRead }.count
        }
        return dataService.unreadCountForCategory(category.id)
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = MockDataService.shared) {
        self.dataService = dataService
        self.selectedCategory = Category.allUpdates
        loadArticles()
    }

    // MARK: - Actions

    /// Load articles from the data service
    func loadArticles() {
        articles = dataService.articles.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Refresh articles (simulates network fetch)
    func refresh() async {
        isRefreshing = true

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            loadArticles()
            isRefreshing = false
        }
    }

    /// Select a category
    func selectCategory(_ category: Category) {
        withAnimation(Design.Animation.standard) {
            selectedCategory = category
        }
    }

    /// Toggle bookmark status for an article
    func toggleBookmark(for article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index].isBookmarked.toggle()
        }
    }

    /// Mark an article as read
    func markAsRead(_ article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index].isRead = true
        }
    }

    /// Mark an article as unread
    func markAsUnread(_ article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index].isRead = false
        }
    }

    // MARK: - Helper Methods

    /// Get the source for an article
    func source(for article: Article) -> Source? {
        dataService.source(for: article.sourceID)
    }

    /// Get the category for an article
    func category(for article: Article) -> Category? {
        dataService.category(for: article.categoryID)
    }
}
