//
//  ArchiveViewModel.swift
//  OpenRSS
//
//  ViewModel for the Archive view — shows fully decayed, aged-out articles.
//

import Foundation
import SwiftUI

@Observable
final class ArchiveViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService

    // MARK: - State

    var searchViewModel = SearchViewModel(mode: .titleOnly)

    // MARK: - Computed Properties

    var filteredArticles: [Article] {
        dataService.articles
            .filter { $0.isArchived }
            .filter { searchViewModel.matches($0) }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    // MARK: - Initialization

    init(dataService: FeedDataService = SwiftDataService.shared) {
        self.dataService = dataService
    }

    // MARK: - Helpers

    func source(for article: Article) -> Source? {
        dataService.source(for: article.sourceID)
    }

    func toggleBookmark(for article: Article) {
        dataService.toggleBookmark(for: article.id)
    }

    func markAsRead(_ article: Article) {
        dataService.markAsRead(article.id)
    }
}
