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

    /// Dedicated search ViewModel — owns the query string and filter strategy.
    /// The View binds directly to `searchViewModel.searchText`.
    var searchViewModel = SearchViewModel(mode: .titleOnly)

    /// The set of active filter options. Empty means "show everything".
    var activeFilters: Set<FilterOption> = []

    /// True when at least one filter is toggled on — used to show the badge dot.
    var hasActiveFilters: Bool { !activeFilters.isEmpty }

    // MARK: - Computed Properties

    /// All categories including "All Updates"
    var allCategories: [Category] {
        [Category.allUpdates] + dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Articles filtered by the selected category then by the search query.
    /// Category logic lives here; search filtering is delegated to SearchViewModel.
    var filteredArticles: [Article] {
        var result = articles

        // 1. Limit to the past 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        result = result.filter { $0.publishedAt >= sevenDaysAgo }

        // 2. Filter by selected category
        if let category = selectedCategory, category.id != Category.allUpdates.id {
            result = result.filter { $0.categoryID == category.id }
        }

        // 2. Delegate search filtering to SearchViewModel (Strategy Pattern)
        result = searchViewModel.filteredArticles(from: result)

        // 3. Apply each active filter option
        for filter in activeFilters {
            switch filter {
            case .saved:
                result = result.filter { $0.isBookmarked }
            case .unread:
                result = result.filter { !$0.isRead }
            case .today:
                result = result.filter { Calendar.current.isDateInToday($0.publishedAt) }
            }
        }

        return result.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// True when the user has at least one subscribed feed — drives the empty state in TodayView.
    var hasSources: Bool { !dataService.sources.isEmpty }

    /// Unread count for a specific category
    func unreadCount(for category: Category) -> Int {
        if category.id == Category.allUpdates.id {
            return dataService.articles.filter { !$0.isRead }.count
        }
        return dataService.unreadCountForCategory(category.id)
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = SwiftDataService.shared) {
        self.dataService = dataService
        self.selectedCategory = Category.allUpdates
        loadArticles()
    }

    // MARK: - Actions

    /// Load articles from the data service
    func loadArticles() {
        articles = dataService.articles.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// Refresh articles from all subscribed feeds, then prune old cache.
    func refresh() async {
        print("🔄 TodayViewModel.refresh() CALLED")
        isRefreshing = true
        defer { isRefreshing = false }

        if let sds = dataService as? SwiftDataService {
            await sds.refreshAllFeeds()
            // Purge extracted article cache entries older than 7 days
            sds.purgeOldArticleCache(olderThan: 7)
        }

        loadArticles()
        print("✅ loadArticles DONE. viewModel articles =", articles.count)
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
