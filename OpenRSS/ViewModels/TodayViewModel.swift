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

    /// Articles filtered by category, search, and active filters in a single pass.
    /// Reads directly from `dataService.articles` — no duplicate array stored.
    var filteredArticles: [Article] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let category = selectedCategory
        let isAllUpdates = category == nil || category?.id == Category.allUpdates.id
        let filters = activeFilters
        let checkToday = filters.contains(.today)
        let checkSaved = filters.contains(.saved)
        let checkUnread = filters.contains(.unread)

        return dataService.articles.filter { article in
            // 1. 7-day recency (exception: YouTube playlist feeds)
            if article.publishedAt < sevenDaysAgo {
                guard let source = dataService.source(for: article.sourceID),
                      source.feedURL.contains("playlist_id=") else {
                    return false
                }
            }

            // 2. Category
            if !isAllUpdates, article.categoryID != category!.id {
                return false
            }

            // 3. Search
            if !searchViewModel.matches(article) {
                return false
            }

            // 4. Active filters
            if checkSaved && !article.isBookmarked { return false }
            if checkUnread && article.isRead { return false }
            if checkToday && !Calendar.current.isDateInToday(article.publishedAt) { return false }

            return true
        }.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// True when the user has at least one subscribed feed — drives the empty state in TodayView.
    var hasSources: Bool { !dataService.sources.isEmpty }

    /// Unread count for a specific category (respects the same 7-day + playlist exception as the view).
    func unreadCount(for category: Category) -> Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let visible = dataService.articles.filter { article in
            guard !article.isRead else { return false }
            if article.publishedAt >= sevenDaysAgo { return true }
            if let source = dataService.source(for: article.sourceID),
               source.feedURL.contains("playlist_id=") {
                return true
            }
            return false
        }
        if category.id == Category.allUpdates.id {
            return visible.count
        }
        return visible.filter { $0.categoryID == category.id }.count
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = SwiftDataService.shared) {
        self.dataService = dataService
        self.selectedCategory = Category.allUpdates
    }

    // MARK: - Refresh Key

    private static let lastRefreshKey = "openrss.lastRefresh"

    // MARK: - Actions

    /// Refresh articles from all subscribed feeds, then prune old cache.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        if let sds = dataService as? SwiftDataService {
            await sds.refreshAllFeeds()
            // Purge extracted article cache entries older than 30 days
            sds.purgeOldArticleCache(olderThan: 30)
        }

        UserDefaults.standard.set(Date(), forKey: Self.lastRefreshKey)
    }

    /// Called automatically on first appearance of TodayView (via .task).
    ///
    /// Skips the network fetch if a successful refresh happened within the last
    /// 30 minutes — the cached articles already shown are fresh enough.
    /// Skips entirely when the user has no subscribed feeds.
    func autoRefreshIfNeeded() async {
        guard hasSources else { return }

        let lastRefresh = UserDefaults.standard.object(forKey: Self.lastRefreshKey) as? Date
        let isStale = lastRefresh.map { Date().timeIntervalSince($0) > 1800 } ?? true
        guard isStale else { return }

        await refresh()
    }

    /// Select a category
    func selectCategory(_ category: Category) {
        withAnimation(Design.Animation.standard) {
            selectedCategory = category
        }
    }

    /// Toggle bookmark status for an article
    func toggleBookmark(for article: Article) {
        dataService.toggleBookmark(for: article.id)
    }

    /// Mark an article as read
    func markAsRead(_ article: Article) {
        dataService.markAsRead(article.id)
    }

    /// Mark an article as unread
    func markAsUnread(_ article: Article) {
        dataService.markAsUnread(article.id)
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
