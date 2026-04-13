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

    // MARK: - Search

    /// Title-only fuzzy search over this source's cached articles.
    /// Bind UI to `searchViewModel.searchText`.
    var searchViewModel = SearchViewModel(mode: .titleOnly)

    // MARK: - Computed Properties

    var source: Source? {
        dataService.source(for: sourceID)
    }

    /// Full cached list for this source, minus any hidden YouTube kinds.
    /// This is the pre-search list — `articleCount` reflects this.
    private var allArticles: [Article] {
        let all = dataService.articlesForSource(sourceID)
        guard let hidden = dataService.source(for: sourceID)?.hiddenYouTubeKinds,
              !hidden.isEmpty else {
            return all
        }
        return all.filter { article in
            // Non-YouTube / unclassifiable items are always shown.
            guard let kind = YouTubeService.contentKind(forArticleURL: article.articleURL) else {
                return true
            }
            return !hidden.contains(kind)
        }
    }

    /// Articles the view iterates — `allArticles` filtered by the active search query.
    /// When the query is empty, `matches(_:)` returns true so this equals `allArticles`.
    var articles: [Article] {
        allArticles.filter { searchViewModel.matches($0) }
    }

    /// Total cached articles for this source (unfiltered by search).
    /// Header subtitle uses this so the count stays stable while typing.
    var articleCount: Int {
        allArticles.count
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
