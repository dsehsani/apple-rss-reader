//
//  SwiftDataService.swift
//  OpenRSS
//
//  @Observable singleton implementing FeedDataService via SwiftData.
//  Replaces MockDataService as the live data source.
//
//  Data flow:
//    SwiftData (SQLite) → loadFromSwiftData() → categories/sources arrays
//    → TodayViewModel / MyFeedsViewModel / SourcesViewModel (via FeedDataService)
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - SwiftDataService

@Observable
final class SwiftDataService: FeedDataService {

    // MARK: - Singleton

    // init() is nonisolated (no @MainActor on the class), so this is fine.
    // Methods that touch ModelContext are individually marked @MainActor.
    static let shared = SwiftDataService()

    // MARK: - FeedDataService — Observable Properties

    private(set) var categories: [Category] = []
    private(set) var sources: [Source] = []
    /// In-memory articles fetched from live RSS feeds. Not persisted.
    private(set) var articles: [Article] = []

    // MARK: - Internal

    private var modelContext: ModelContext?

    // MARK: - Constants

    /// Feeds with no assigned folder use this sentinel UUID as their `categoryID`.
    /// It never corresponds to a real FolderModel in SwiftData.
    static let unfiledFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!

    // MARK: - Initialization

    private init() {}

    // MARK: - Bootstrap

    /// Called once from `OpenRSSApp.init()` after the ModelContainer is created.
    ///
    /// Loads persisted feeds/folders from SwiftData, then immediately hydrates
    /// the in-memory `articles` array from the JSON cache so the Today feed is
    /// pre-populated before the first network refresh completes.
    @MainActor
    func configure(container: ModelContainer) {
        self.modelContext = container.mainContext
        loadFromSwiftData()

        // Pre-populate articles from the local cache so the UI is non-empty
        // on launch even before the first RSS refresh finishes.
        let cached = ArticleCacheStore.load()
        if !cached.isEmpty {
            self.articles = cached
        }
    }

    // MARK: - Load

    /// Re-reads all FolderModel and FeedModel records and maps them to domain models.
    /// Called after every write so that `@Observable` property changes propagate to views.
    @MainActor
    func loadFromSwiftData() {
        guard let context = modelContext else { return }

        let folderDescriptor = FetchDescriptor<FolderModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let feedDescriptor = FetchDescriptor<FeedModel>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )

        do {
            let folders = try context.fetch(folderDescriptor)
            let feeds   = try context.fetch(feedDescriptor)

            self.categories = folders.map { Category(from: $0) }
            self.sources    = feeds.map   { Source(from: $0) }
        } catch {
            print("SwiftDataService load error: \(error)")
        }
    }

    // MARK: - FeedDataService Protocol

    func source(for id: UUID) -> Source? {
        sources.first { $0.id == id }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    func articlesForCategory(_ categoryID: UUID) -> [Article] {
        articles.filter { $0.categoryID == categoryID }
                .sorted { $0.publishedAt > $1.publishedAt }
    }

    func articlesForSource(_ sourceID: UUID) -> [Article] {
        articles.filter { $0.sourceID == sourceID }
                .sorted { $0.publishedAt > $1.publishedAt }
    }

    func unreadCountForCategory(_ categoryID: UUID) -> Int {
        articles.filter { $0.categoryID == categoryID && !$0.isRead }.count
    }

    func unreadCountForSource(_ sourceID: UUID) -> Int {
        articles.filter { $0.sourceID == sourceID && !$0.isRead }.count
    }

    func toggleBookmark(for articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isBookmarked.toggle()
        }
    }

    func markAsRead(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = true
        }
    }

    func markAsUnread(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = false
        }
    }

    // MARK: - CRUD: Folders

    /// Creates a new folder and persists it.
    @MainActor
    func addFolder(name: String, iconName: String = "folder.fill", colorHex: String = "007AFF") throws {
        guard let context = modelContext else { return }
        let folder = FolderModel(name: name, sortOrder: categories.count, iconName: iconName, colorHex: colorHex)
        context.insert(folder)
        try context.save()
        loadFromSwiftData()
    }

    /// Permanently deletes a folder (cascade-deletes all its feeds).
    @MainActor
    func deleteFolder(id: UUID) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FolderModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let folder = try context.fetch(descriptor).first {
            context.delete(folder)
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Returns the live FolderModel for a given UUID (used when assigning a feed to a folder).
    @MainActor
    func folderModel(for id: UUID) -> FolderModel? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<FolderModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - CRUD: Feeds

    /// Creates a new feed subscription and optionally assigns it to a folder.
    @MainActor
    func addFeed(feedURL: String, title: String, websiteURL: String, folderID: UUID?) throws {
        guard let context = modelContext else { return }
        let feed = FeedModel(feedURL: feedURL, title: title, websiteURL: websiteURL)
        if let folderID {
            feed.folder = folderModel(for: folderID)
        }
        context.insert(feed)
        try context.save()
        loadFromSwiftData()
    }

    /// Permanently deletes a feed subscription.
    @MainActor
    func deleteFeed(id: UUID) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let feed = try context.fetch(descriptor).first {
            context.delete(feed)
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Toggles whether a feed is included in refresh.
    @MainActor
    func toggleFeedEnabled(id: UUID) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let feed = try context.fetch(descriptor).first {
            feed.isEnabled.toggle()
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Toggles whether all articles from this feed are treated as paywalled.
    @MainActor
    func toggleFeedPaywalled(id: UUID) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let feed = try context.fetch(descriptor).first {
            feed.isPaywalled.toggle()
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Sets a per-feed decay override (or clears it with nil).
    @MainActor
    func setDecayOverride(feedID: UUID, tier: VelocityTier?) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == feedID }
        )
        if let feed = try context.fetch(descriptor).first {
            feed.decayOverride = tier
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Marks the in-memory article with the given id as paywalled.
    /// Called by ArticleReaderHostView when post-pipeline detection fires.
    @MainActor
    func markArticlePaywalled(id: UUID) {
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
        articles[index].isPaywalled = true
    }

    // MARK: - RSS Refresh

    /// Fetches live articles from every enabled source and updates the in-memory `articles` array.
    /// Mirrors the logic from `MockDataService.refreshAllFeeds()`.
    @MainActor
    func refreshAllFeeds() async {
        let rssService = RSSService()
        var newArticles: [Article] = []
        var seen = Set<String>()

        for source in sources where source.isEnabled {
            guard let url = URL(string: source.feedURL) else { continue }

            do {
                // Fetch the raw feed data so we can run both FeedKit and (for
                // YouTube) our custom media:group parser on the same bytes.
                let feedData = try await rssService.fetchFeedData(from: url)
                let parsed   = try await rssService.parseFeed(from: feedData)


                // For YouTube Atom feeds, FeedKit does not map media:description
                // or media:thumbnail inside media:group. Run our lightweight SAX
                // parser to extract those fields from the raw XML.
                var youtubeExtras: [String: YouTubeAtomParser.VideoMeta] = [:]
                if YouTubeService.isYouTubeURL(url) {
                    youtubeExtras = YouTubeAtomParser().parse(data: feedData)
                }

                let converted: [Article] = parsed.compactMap { p in
                    guard let title = p.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !title.isEmpty else { return nil }

                    let linkKey = (p.link ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = linkKey.isEmpty
                        ? "\(source.id.uuidString)|\(title)"
                        : "\(source.id.uuidString)|\(linkKey)"
                    guard seen.insert(key).inserted else { return nil }

                    // Supplement FeedKit's parse with YouTube media:group fields.
                    let ytMeta   = youtubeExtras[linkKey]
                    let rawExcerpt = p.description
                        ?? ytMeta?.description
                        ?? ""
                    let excerpt = plainText(rawExcerpt)

                    let now = Date()
                    let rawPublished = p.publicationDate ?? now
                    let published = Article.validatedPublishDate(
                        rawPublished, fetchedAt: now, feedName: source.name
                    )
                    let wordCount = excerpt.split { $0.isWhitespace || $0.isNewline }.count
                    let minutes   = max(1, min(30, wordCount / 200))

                    // Image priority:
                    //   1. FeedKit media:content / enclosure
                    //   2. YouTubeAtomParser media:thumbnail (inside media:group)
                    //   3. First <img> found in raw description HTML
                    //   4. YouTube hqdefault thumbnail derived from video ID
                    var imageURL = p.imageURL
                        ?? ytMeta?.thumbnailURL
                        ?? firstImageURL(in: p.description)
                    if imageURL == nil, YouTubeService.isYouTubeVideoOrShortURL(linkKey) {
                        imageURL = YouTubeService.videoID(from: linkKey)
                            .flatMap { YouTubeService.thumbnailURL(videoID: $0)?.absoluteString }
                    }

                    return Article(
                        title: title,
                        excerpt: excerpt,
                        sourceID: source.id,
                        categoryID: source.categoryID,
                        imageURL: imageURL,
                        articleURL: linkKey.isEmpty ? "https://example.com" : linkKey,
                        publishedAt: published,
                        fetchedAt: now,
                        isRead: false,
                        readTimeMinutes: minutes
                    )
                }
                newArticles.append(contentsOf: converted)

            } catch {
                // Failed to fetch source; continue with remaining feeds
            }

            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s throttle
        }

        newArticles.sort { $0.publishedAt > $1.publishedAt }

        if !newArticles.isEmpty {
            // Auto-infer velocity tiers based on article frequency
            recalculateVelocityTiers(articles: newArticles)

            // Archive fully-decayed, old, unread, non-bookmarked articles
            applyArchiveRule(&newArticles)

            self.articles = newArticles
            // Persist to the local JSON cache so the next launch is pre-populated.
            ArticleCacheStore.save(newArticles)
        } else {
            // 0 articles fetched; keep existing articles
        }
    }

    // MARK: - Velocity Tier Inference (Task 2)

    /// Recalculates the velocity tier for each feed based on articles fetched
    /// in the last 30 days. Only writes to SwiftData when the tier actually changed.
    @MainActor
    private func recalculateVelocityTiers(articles: [Article]) {
        guard let context = modelContext else { return }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        // Group articles by sourceID and count those within the last 30 days
        var countBySource: [UUID: Int] = [:]
        for article in articles {
            if article.fetchedAt >= thirtyDaysAgo {
                countBySource[article.sourceID, default: 0] += 1
            }
        }

        let descriptor = FetchDescriptor<FeedModel>()
        guard let feeds = try? context.fetch(descriptor) else { return }

        var changed = false
        for feed in feeds {
            let count = countBySource[feed.id] ?? 0
            let postsPerDay = Double(count) / 30.0
            let newTier = VelocityTier.from(postsPerDay: postsPerDay)
            if feed.velocityTier != newTier {
                feed.velocityTier = newTier
                changed = true
            }
        }

        if changed {
            try? context.save()
            loadFromSwiftData()
        }
    }

    // MARK: - Archive Rule (Task 7)

    /// Marks articles as archived when they are at the decay floor, older than
    /// 30 days, unread, and not bookmarked.
    private func applyArchiveRule(_ articles: inout [Article]) {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        for i in articles.indices {
            let article = articles[i]
            guard !article.isArchived,
                  !article.isRead,
                  !article.isBookmarked,
                  article.fetchedAt < thirtyDaysAgo else { continue }

            let source = self.source(for: article.sourceID)
            let halfLife = source?.effectiveVelocityTier.halfLifeHours ?? VelocityTier.daily.halfLifeHours
            let score = Article.decayScore(publishedAt: article.publishedAt, halfLifeHours: halfLife)
            if score <= 0.2 {
                articles[i].isArchived = true
            }
        }
    }

    // MARK: - Cache Maintenance

    /// Purges extracted articles from the SwiftData cache that are older than `days` days.
    @MainActor
    func purgeOldArticleCache(olderThan days: Int = CachePolicy.cacheRetentionDays) {
        guard let context = modelContext else { return }
        let service = ArticleCacheService(context: context)
        try? service.purgeOldCache(olderThan: days)
    }

    // MARK: - Private Helpers

    /// Extracts the first `src` URL from an `<img>` tag in raw HTML.
    /// Handles both single- and double-quoted src attributes.
    /// Returns nil if no `<img>` with an absolute URL is found.
    private func firstImageURL(in html: String?) -> String? {
        guard let html else { return nil }
        // Target only <img> tags to avoid picking up <script src> or <link src>.
        // The alternation handles both double- and single-quoted src values.
        let pattern = #"<img\b[^>]*?\bsrc=(?:"([^"]+)"|'([^']+)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return nil }
        let nsRange = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: nsRange) {
            // Group 1 = double-quoted value, group 2 = single-quoted value.
            let srcRange = Range(match.range(at: 1), in: html)
                        ?? Range(match.range(at: 2), in: html)
            guard let srcRange else { continue }
            let candidate = String(html[srcRange])
            if candidate.hasPrefix("http") { return candidate }
        }
        return nil
    }

    private func plainText(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&#39;",   with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Domain Model Mapping

private extension Category {
    /// Maps a SwiftData `FolderModel` to the `Category` domain model.
    /// Icon and color come from the user's selection stored on the model.
    init(from model: FolderModel) {
        self.init(
            id:        model.id,
            name:      model.name,
            icon:      model.iconName,
            color:     Color(hex: model.colorHex),
            sortOrder: model.sortOrder
        )
    }
}

private extension Source {
    /// Maps a SwiftData `FeedModel` to the `Source` domain model.
    /// Feeds without a folder use the sentinel `unfiledFolderID` as their `categoryID`.
    init(from model: FeedModel) {
        self.init(
            id:          model.id,
            name:        model.title,
            feedURL:     model.feedURL,
            websiteURL:  model.websiteURL,
            icon:        "dot.radiowaves.left.and.right",
            iconColor:   .blue,
            categoryID:  model.folder?.id ?? SwiftDataService.unfiledFolderID,
            isEnabled:   model.isEnabled,
            isPaywalled: model.isPaywalled,
            addedAt:     model.addedAt,
            velocityTier: model.velocityTier,
            decayOverride: model.decayOverride
        )
    }
}
