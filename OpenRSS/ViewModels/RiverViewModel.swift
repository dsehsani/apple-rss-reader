//
//  RiverViewModel.swift
//  OpenRSS
//
//  Phase 2a — Replaces TodayViewModel with River-pipeline-driven data.
//  Subscribes to RiverPipeline's snapshot publisher and converts
//  FeedItems to Articles for the existing ArticleCardView via a
//  conversion layer.
//
//  Ports the category-filter, search, and filter logic from TodayViewModel.
//

import Foundation
import SwiftUI
import Combine

// MARK: - RiverViewModel

@MainActor @Observable
final class RiverViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService
    private let pipeline = RiverPipeline.shared

    // MARK: - Published State

    var selectedCategory: Category?
    var isRefreshing: Bool = false

    /// Dedicated search ViewModel — owns the query string and filter strategy.
    var searchViewModel = SearchViewModel(mode: .titleOnly)

    /// The set of active filter options. Empty means "show everything".
    var activeFilters: Set<FilterOption> = []

    /// True when at least one filter is toggled on.
    var hasActiveFilters: Bool { !activeFilters.isEmpty }

    /// Last pipeline run duration in milliseconds (for diagnostics).
    var lastPipelineDurationMs: Double = 0

    // MARK: - River State

    /// Raw RiverItems from the pipeline snapshot.
    private var riverItems: [RiverItem] = []

    /// Cancellables for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// All categories including "All Updates".
    var allCategories: [Category] {
        [Category.allUpdates] + dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Articles converted from river items, filtered by category, search, and active filters.
    /// This is the primary data source for the view.
    var filteredArticles: [Article] {
        let category = selectedCategory
        let isAllUpdates = category == nil || category?.id == Category.allUpdates.id
        let filters = activeFilters
        let checkToday = filters.contains(.today)
        let checkSaved = filters.contains(.saved)
        let checkUnread = filters.contains(.unread)

        return riverItems.compactMap { riverItem -> (Article, Double)? in
            guard case .article(let feedItem) = riverItem else { return nil }

            // Look up the source to get the categoryID
            guard let source = dataService.source(for: feedItem.sourceID) else { return nil }
            let article = feedItem.toArticle(categoryID: source.categoryID)

            // Category filter
            if !isAllUpdates, article.categoryID != category!.id {
                return nil
            }

            // Search filter
            if !searchViewModel.matches(article) {
                return nil
            }

            // Active filters
            if checkSaved && !article.isBookmarked { return nil }
            if checkUnread && article.isRead { return nil }
            if checkToday && !Calendar.current.isDateInToday(article.publishedAt) { return nil }

            return (article, riverItem.relevanceScore)
        }
        // Sort by relevance score (already sorted from pipeline, but re-sort after filtering)
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    /// Filtered river items including both articles and cluster cards.
    /// Cluster cards have their sourceNames resolved to human-readable names.
    var filteredRiverItems: [RiverItem] {
        let category = selectedCategory
        let isAllUpdates = category == nil || category?.id == Category.allUpdates.id

        return riverItems.compactMap { riverItem -> (RiverItem, Double)? in
            switch riverItem {
            case .article(let feedItem):
                guard let source = dataService.source(for: feedItem.sourceID) else { return nil }
                let article = feedItem.toArticle(categoryID: source.categoryID)

                // Category filter
                if !isAllUpdates, article.categoryID != category!.id {
                    return nil
                }
                // Search filter
                if !searchViewModel.matches(article) {
                    return nil
                }
                return (riverItem, riverItem.relevanceScore)

            case .cluster(let card):
                // Category filter: check the canonical item's source category
                if !isAllUpdates {
                    guard let source = dataService.source(for: card.canonicalItem.sourceID),
                          source.categoryID == category!.id else {
                        return nil
                    }
                }
                // Resolve source names from UUID strings to human-readable names
                let resolvedCard = resolveClusterSourceNames(card)
                return (.cluster(resolvedCard), riverItem.relevanceScore)

            case .digest(let card):
                // Resolve source name if it's a UUID placeholder
                let resolvedCard = resolveDigestSourceName(card)
                return (.digest(resolvedCard), riverItem.relevanceScore)

            case .nudge(let card):
                // Resolve source name for nudge cards too
                let resolvedCard = resolveNudgeSourceName(card)
                return (.nudge(resolvedCard), riverItem.relevanceScore)
            }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    /// True when the user has at least one subscribed feed.
    var hasSources: Bool { !dataService.sources.isEmpty }

    /// Returns the relevance score for a given article ID (for decay opacity).
    func relevanceScore(for articleID: UUID) -> Double {
        for item in riverItems {
            switch item {
            case .article(let feedItem):
                if feedItem.id == articleID { return feedItem.relevanceScore }
            case .cluster(let card):
                if card.canonicalItem.id == articleID { return card.canonicalItem.relevanceScore }
            default:
                break
            }
        }
        return 1.0
    }

    /// Returns the source for a given sourceID (used by DigestCardView and NudgeCardView).
    func source(forSourceID sourceID: UUID) -> Source? {
        dataService.source(for: sourceID)
    }

    /// Resolves UUID-string source name in a DigestCard to a human-readable name.
    private func resolveDigestSourceName(_ card: DigestCard) -> DigestCard {
        if let source = dataService.source(for: card.sourceID) {
            return DigestCard(
                sourceID: card.sourceID,
                sourceName: source.name,
                itemCount: card.itemCount,
                highlights: card.highlights,
                overflowIDs: card.overflowIDs,
                insertionPosition: card.insertionPosition
            )
        }
        return card
    }

    /// Resolves UUID-string source name in a NudgeCard to a human-readable name.
    private func resolveNudgeSourceName(_ card: NudgeCard) -> NudgeCard {
        if let source = dataService.source(for: card.sourceID) {
            return NudgeCard(
                sourceID: card.sourceID,
                sourceName: source.name,
                itemCount: card.itemCount,
                message: "\(source.name) posted \(card.itemCount) articles in the last 2 hours",
                timestamp: card.timestamp
            )
        }
        return card
    }

    /// Resolves UUID-string source names in a ClusterCard to human-readable names.
    private func resolveClusterSourceNames(_ card: ClusterCard) -> ClusterCard {
        let resolvedNames = card.sourceNames.compactMap { uuidStr -> String? in
            guard let uuid = UUID(uuidString: uuidStr),
                  let source = dataService.source(for: uuid) else {
                return uuidStr  // fallback to UUID string
            }
            return source.name
        }
        return ClusterCard(
            id: card.id,
            canonicalItem: card.canonicalItem,
            sourceCount: max(card.sourceCount, resolvedNames.count),
            sourceNames: resolvedNames,
            allItemIDs: card.allItemIDs,
            allItems: card.allItems
        )
    }

    /// Unread count for a specific category.
    func unreadCount(for category: Category) -> Int {
        // Use the data service's articles for unread counts (consistent with bookmark/read state)
        let visible = dataService.articles.filter { !$0.isRead }
        if category.id == Category.allUpdates.id {
            return visible.count
        }
        return visible.filter { $0.categoryID == category.id }.count
    }

    // MARK: - Initialization

    init(dataService: FeedDataService? = nil) {
        let resolvedService: FeedDataService = dataService ?? SwiftDataService.shared
        self.dataService = resolvedService
        self.selectedCategory = Category.allUpdates

        // Subscribe to pipeline snapshots
        pipeline.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.riverItems = snapshot.items
                    self.lastPipelineDurationMs = snapshot.pipelineDurationMs
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh Key

    private static let lastRefreshKey = "openrss.lastRiverRefresh"

    // MARK: - Actions

    /// Triggers a full pipeline cycle: fetch, score, snapshot.
    /// Pipeline results are synced back to SwiftDataService for legacy UI compat
    /// without re-fetching feeds over the network.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let sources = dataService.sources
        await pipeline.runCycle(sources: sources)

        // Sync pipeline FeedItems back to SwiftDataService as Articles
        // so legacy views (bookmark state, read state) stay in sync
        // without making a second round of HTTP requests.
        if let sds = dataService as? SwiftDataService {
            let feedItems = SQLiteStore.shared.fetchRiverItems()
            let articles: [Article] = feedItems.compactMap { feedItem in
                guard let source = sds.source(for: feedItem.sourceID) else { return nil }
                return feedItem.toArticle(categoryID: source.categoryID)
            }
            sds.syncArticles(articles)
        }

        UserDefaults.standard.set(Date(), forKey: Self.lastRefreshKey)
    }

    /// Called automatically on first appearance. Skips if a refresh happened
    /// within the last 30 minutes.
    func autoRefreshIfNeeded() async {
        guard hasSources else { return }

        let lastRefresh = UserDefaults.standard.object(forKey: Self.lastRefreshKey) as? Date
        let isStale = lastRefresh.map { Date().timeIntervalSince($0) > 1800 } ?? true

        if isStale {
            await refresh()
        } else {
            // Just re-score existing items (decay may have changed)
            pipeline.runScoringCycle()
        }
    }

    /// Select a category.
    func selectCategory(_ category: Category) {
        withAnimation(Design.Animation.standard) {
            selectedCategory = category
        }
    }

    /// Toggle bookmark status for an article.
    func toggleBookmark(for article: Article) {
        dataService.toggleBookmark(for: article.id)
    }

    /// Mark an article as read.
    func markAsRead(_ article: Article) {
        dataService.markAsRead(article.id)
    }

    /// Mark an article as unread.
    func markAsUnread(_ article: Article) {
        dataService.markAsUnread(article.id)
    }

    // MARK: - Helper Methods

    /// Get the source for an article.
    func source(for article: Article) -> Source? {
        dataService.source(for: article.sourceID)
    }

    /// Get the source for a FeedItem (used by ClusterCardView).
    func source(for feedItem: FeedItem) -> Source? {
        dataService.source(for: feedItem.sourceID)
    }

    /// Get the category for an article.
    func category(for article: Article) -> Category? {
        dataService.category(for: article.categoryID)
    }
}
