//
//  FolderViewModel.swift
//  OpenRSS
//
//  ViewModel for browsing all articles within a category/folder.
//

import Foundation
import SwiftUI

@Observable
final class FolderViewModel {

    // MARK: - Dependencies

    private let dataService: FeedDataService
    let categoryID: UUID

    // MARK: - Filter State

    enum FolderFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case saved = "Saved"
    }

    var activeFilter: FolderFilter = .all

    // MARK: - Computed Properties

    var category: Category? {
        dataService.category(for: categoryID)
    }

    var sources: [Source] {
        dataService.sources.filter { $0.categoryID == categoryID }
    }

    var feedCount: Int { sources.count }

    var filteredArticles: [Article] {
        var articles = dataService.articlesForCategory(categoryID)
            .filter { $0.isCanonical }

        switch activeFilter {
        case .all: break
        case .unread: articles = articles.filter { !$0.isRead }
        case .saved: articles = articles.filter { $0.isBookmarked }
        }

        // Decay sort over full 30-day window
        return articles.sorted { a1, a2 in
            let s1 = dataService.source(for: a1.sourceID)
            let s2 = dataService.source(for: a2.sourceID)

            let grace1 = s1?.isInGracePeriod ?? false
            let grace2 = s2?.isInGracePeriod ?? false

            if grace1 && !grace2 { return true }
            if !grace1 && grace2 { return false }
            if grace1 && grace2 { return a1.publishedAt > a2.publishedAt }

            let hl1 = s1?.effectiveVelocityTier.halfLifeHours ?? VelocityTier.daily.halfLifeHours
            let hl2 = s2?.effectiveVelocityTier.halfLifeHours ?? VelocityTier.daily.halfLifeHours
            let score1 = Article.riverScore(
                decayScore: Article.decayScore(publishedAt: a1.publishedAt, halfLifeHours: hl1),
                clusterSize: a1.clusterSize,
                preferUniqueStories: s1?.preferUniqueStories ?? false
            )
            let score2 = Article.riverScore(
                decayScore: Article.decayScore(publishedAt: a2.publishedAt, halfLifeHours: hl2),
                clusterSize: a2.clusterSize,
                preferUniqueStories: s2?.preferUniqueStories ?? false
            )
            return score1 > score2
        }
    }

    var totalArticleCount: Int {
        dataService.articlesForCategory(categoryID).count
    }

    var feedNames: String {
        let names = sources.map(\.name)
        if names.count <= 3 {
            return names.joined(separator: ", ")
        }
        let shown = names.prefix(2).joined(separator: ", ")
        return "\(shown), +\(names.count - 2) more"
    }

    // MARK: - Initialization

    init(categoryID: UUID, dataService: FeedDataService = SwiftDataService.shared) {
        self.categoryID = categoryID
        self.dataService = dataService
    }

    // MARK: - Helpers

    func source(for article: Article) -> Source? {
        dataService.source(for: article.sourceID)
    }

    func decayScore(for article: Article) -> Double {
        guard let source = dataService.source(for: article.sourceID) else { return 1.0 }
        if source.isInGracePeriod { return 1.0 }
        let halfLife = source.effectiveVelocityTier.halfLifeHours
        return Article.decayScore(publishedAt: article.publishedAt, halfLifeHours: halfLife)
    }

    func toggleBookmark(for article: Article) {
        dataService.toggleBookmark(for: article.id)
    }

    func markAsRead(_ article: Article) {
        dataService.markAsRead(article.id)
    }

    /// Returns a cluster badge describing how this canonical article groups siblings.
    /// nil when the article is standalone. `onSiblingTap` is left nil so the view
    /// can wire up its own navigation closure.
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
}
