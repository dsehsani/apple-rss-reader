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

    var searchViewModel = SearchViewModel(mode: .titleOnly)

    // MARK: - Computed Properties

    var source: Source? {
        dataService.source(for: sourceID)
    }

    /// Full cached list for this source, minus any hidden YouTube kinds.
    private var allArticles: [Article] {
        let all = dataService.articlesForSource(sourceID)
        guard let hidden = dataService.source(for: sourceID)?.hiddenYouTubeKinds,
              !hidden.isEmpty else {
            return all
        }
        return all.filter { article in
            guard let kind = YouTubeService.contentKind(forArticleURL: article.articleURL) else {
                return true
            }
            return !hidden.contains(kind)
        }
    }

    var articles: [Article] {
        let filtered = allArticles.filter { searchViewModel.matches($0) }

        // When the user has turned on "Prefer unique stories" for this source,
        // sink articles that belong to multi-item clusters below unique ones by
        // sorting on the same `riverScore` formula the Today/Discover river uses.
        // Otherwise keep the strict chronological order from `articlesForSource`.
        guard let source = dataService.source(for: sourceID),
              source.preferUniqueStories else {
            return filtered
        }

        let halfLife = source.effectiveVelocityTier.halfLifeHours
        return filtered.sorted { a1, a2 in
            let s1 = Article.riverScore(
                decayScore: Article.decayScore(
                    publishedAt: a1.publishedAt,
                    halfLifeHours: halfLife
                ),
                clusterSize: a1.clusterSize,
                preferUniqueStories: true
            )
            let s2 = Article.riverScore(
                decayScore: Article.decayScore(
                    publishedAt: a2.publishedAt,
                    halfLifeHours: halfLife
                ),
                clusterSize: a2.clusterSize,
                preferUniqueStories: true
            )
            return s1 > s2
        }
    }

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
