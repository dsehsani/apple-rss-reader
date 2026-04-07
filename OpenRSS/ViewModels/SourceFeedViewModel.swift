//
//  SourceFeedViewModel.swift
//  OpenRSS
//
//  ViewModel for viewing all cached articles from a single source.
//

import Foundation
import SwiftUI

@Observable
final class SourceFeedViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService
    let sourceID: UUID

    // MARK: - Computed Properties

    var source: Source? {
        dataService.source(for: sourceID)
    }

    var articles: [Article] {
        dataService.articlesForSource(sourceID)
    }

    var articleCount: Int {
        articles.count
    }

    // MARK: - Initialization

    init(sourceID: UUID, dataService: FeedDataService = SwiftDataService.shared) {
        self.sourceID = sourceID
        self.dataService = dataService
    }

    // MARK: - Actions

    func toggleBookmark(for article: Article) {
        dataService.toggleBookmark(for: article.id)
    }

    func markAsRead(_ article: Article) {
        dataService.markAsRead(article.id)
    }
}
