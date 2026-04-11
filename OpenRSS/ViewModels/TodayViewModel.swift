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

    /// True when the search bar is active with a non-empty query.
    var isSearchActive: Bool { searchViewModel.hasActiveQuery }

    /// Articles filtered by category, search, and active filters in a single pass.
    /// Reads directly from `dataService.articles` — no duplicate array stored.
    var filteredArticles: [Article] {
        // Search mode: full 30-day cache, no filters, no decay sort
        if isSearchActive {
            return dataService.articles
                .filter { searchViewModel.matches($0) }
                .sorted { $0.publishedAt > $1.publishedAt }
        }

        // Normal mode: existing decay-scored, filtered, 7-day windowed logic
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

            // 5. Exclude archived articles
            if article.isArchived { return false }

            // 6. Exclude non-canonical (clustered) articles in normal mode.
            // Search mode above intentionally returns every match regardless of cluster status.
            if !article.isCanonical { return false }

            return true
        }.sorted { article1, article2 in
            let source1 = dataService.source(for: article1.sourceID)
            let source2 = dataService.source(for: article2.sourceID)

            // Grace period articles sort chronologically at the top
            let grace1 = source1?.isInGracePeriod ?? false
            let grace2 = source2?.isInGracePeriod ?? false

            if grace1 && !grace2 { return true }
            if !grace1 && grace2 { return false }
            if grace1 && grace2 { return article1.publishedAt > article2.publishedAt }

            // River-scored articles sort by combined decay + cluster dominance descending
            let hl1 = source1?.effectiveVelocityTier.halfLifeHours ?? VelocityTier.daily.halfLifeHours
            let hl2 = source2?.effectiveVelocityTier.halfLifeHours ?? VelocityTier.daily.halfLifeHours
            let score1 = Article.riverScore(
                decayScore: Article.decayScore(publishedAt: article1.publishedAt, halfLifeHours: hl1),
                clusterSize: article1.clusterSize,
                preferUniqueStories: source1?.preferUniqueStories ?? false
            )
            let score2 = Article.riverScore(
                decayScore: Article.decayScore(publishedAt: article2.publishedAt, halfLifeHours: hl2),
                clusterSize: article2.clusterSize,
                preferUniqueStories: source2?.preferUniqueStories ?? false
            )
            return score1 > score2
        }
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
            // Purge extracted article cache entries older than the retention window
            sds.purgeOldArticleCache(olderThan: CachePolicy.cacheRetentionDays)
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

    /// Returns a cluster badge describing how this canonical article groups siblings.
    /// nil when the article is standalone (`clusterSize <= 1`).
    ///
    /// The returned badge is partially populated — `onSiblingTap` is left nil
    /// so the view can wire up its own navigation closure (which needs access
    /// to `@State` that the view model cannot see).
    func clusterBadge(for article: Article) -> ClusterBadge? {
        guard article.clusterSize > 1, let clusterID = article.clusterID else { return nil }
        let allInCluster = dataService.articles.filter { $0.clusterID == clusterID }
        let allSameSource = allInCluster.allSatisfy { $0.sourceID == article.sourceID }
        let style: ClusterBadge.Style = allSameSource ? .updates : .sources
        let noun = allSameSource ? "updates" : "sources"

        let siblings: [ClusterBadge.Sibling] = allInCluster
            .filter { $0.id != article.id }
            .sorted { $0.publishedAt > $1.publishedAt }
            .map { sib in
                ClusterBadge.Sibling(
                    article: sib,
                    sourceName: dataService.source(for: sib.sourceID)?.name ?? "Unknown"
                )
            }

        return ClusterBadge(
            label: "\(article.clusterSize) \(noun)",
            style: style,
            siblings: siblings
        )
    }

    /// Dissolves the cluster containing `article`. Reverts on next refresh.
    func splitCluster(for article: Article) {
        dataService.splitCluster(for: article.id)
    }

    /// Returns the decay score for an article, accounting for grace period.
    func decayScore(for article: Article) -> Double {
        guard let source = dataService.source(for: article.sourceID) else { return 1.0 }
        if source.isInGracePeriod { return 1.0 }
        let halfLife = source.effectiveVelocityTier.halfLifeHours
        return Article.decayScore(publishedAt: article.publishedAt, halfLifeHours: halfLife)
    }
}
