//
//  SavedViewModel.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// Sorting options for saved articles
enum SavedSortOption: String, CaseIterable {
    case dateBookmarked = "Date Saved"
    case datePublished = "Date Published"
    case source = "Source"
    case readStatus = "Read Status"
}

/// ViewModel for the Saved articles tab
@Observable
final class SavedViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService

    // MARK: - Published State

    var articles: [Article] = []
    var sortOption: SavedSortOption = .dateBookmarked
    var searchText: String = ""
    var showingFilterSheet: Bool = false

    // MARK: - Computed Properties

    /// Filtered and sorted saved articles
    var filteredArticles: [Article] {
        var result = articles.filter { $0.isBookmarked }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.excerpt.lowercased().contains(query)
            }
        }

        // Apply sorting
        switch sortOption {
        case .dateBookmarked:
            // In real implementation, would track bookmark date
            result.sort { $0.publishedAt > $1.publishedAt }
        case .datePublished:
            result.sort { $0.publishedAt > $1.publishedAt }
        case .source:
            result.sort { article1, article2 in
                let source1 = dataService.source(for: article1.sourceID)?.name ?? ""
                let source2 = dataService.source(for: article2.sourceID)?.name ?? ""
                return source1 < source2
            }
        case .readStatus:
            result.sort { !$0.isRead && $1.isRead }
        }

        return result
    }

    /// Count of saved articles
    var savedCount: Int {
        articles.filter { $0.isBookmarked }.count
    }

    /// Count of unread saved articles
    var unreadSavedCount: Int {
        articles.filter { $0.isBookmarked && !$0.isRead }.count
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = MockDataService.shared) {
        self.dataService = dataService
        loadArticles()
    }

    // MARK: - Actions

    /// Load articles from the data service
    func loadArticles() {
        articles = dataService.articles
    }

    /// Toggle bookmark status for an article
    func toggleBookmark(for article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            withAnimation(Design.Animation.standard) {
                articles[index].isBookmarked.toggle()
            }
        }
    }

    /// Mark an article as read
    func markAsRead(_ article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            articles[index].isRead = true
        }
    }

    /// Remove bookmark (same as toggle, but semantic)
    func removeBookmark(for article: Article) {
        toggleBookmark(for: article)
    }

    /// Change sort option
    func setSortOption(_ option: SavedSortOption) {
        withAnimation(Design.Animation.standard) {
            sortOption = option
        }
    }

    // MARK: - Helper Methods

    /// Get the source for an article
    func source(for article: Article) -> Source? {
        dataService.source(for: article.sourceID)
    }
}
