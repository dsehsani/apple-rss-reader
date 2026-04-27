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
import CryptoKit

// MARK: - Notification Names

extension Notification.Name {
    /// Posted on the main thread whenever a new feed is successfully saved.
    static let feedAdded = Notification.Name("openrss.feedAdded")
}

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
        var cached = ArticleCacheStore.load()
        if !cached.isEmpty {
            ArticleClusteringService.shared.clusterArticles(&cached)
            self.articles = cached
        }

        // One-time migration: seed SQLite with cached articles so the River
        // pipeline has data from the very first launch after the Phase 2 update.
        migrateArticlesToSQLiteIfNeeded(cached)
    }

    // MARK: - SwiftData → SQLite Migration

    private static let migrationKey = "openrss.swiftdata-sqlite-migration-done"

    /// Seeds the SQLite `feed_items` table from the JSON article cache on first launch
    /// after the Phase 2 update. Runs once; subsequent launches skip via UserDefaults flag.
    @MainActor
    private func migrateArticlesToSQLiteIfNeeded(_ cachedArticles: [Article]) {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.migrationKey) }

        guard !cachedArticles.isEmpty else { return }

        let store = SQLiteStore.shared
        let existingCount = store.totalItemCount()
        guard existingCount == 0 else {
            // SQLite already has data — skip migration
            return
        }

        let feedItems: [FeedItem] = cachedArticles.compactMap { article in
            guard let link = URL(string: article.articleURL) else { return nil }
            guard let source = source(for: article.sourceID) else { return nil }

            // Generate a stable ID matching FeedIngestService's key format
            let stableKey = "\(source.id.uuidString)|\(article.articleURL)"
            let id = UUID(name: stableKey)

            return FeedItem(
                id: id,
                sourceID: article.sourceID,
                title: article.title,
                link: link,
                publishedAt: article.publishedAt,
                fetchedAt: article.publishedAt,
                excerpt: article.excerpt,
                imageURL: article.imageURL,
                audioURL: article.audioURL,
                author: nil,
                velocityTier: .article,
                simhashValue: SimHash.compute(article.title)
            )
        }

        if !feedItems.isEmpty {
            store.upsertFeedItems(feedItems)
            print("Migrated \(feedItems.count) articles from cache to SQLite")
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
            upsertArticleState(
                articleURL: articles[i].articleURL,
                isBookmarked: articles[i].isBookmarked
            )
        }
    }

    func markAsRead(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = true
            upsertArticleState(articleURL: articles[i].articleURL, isRead: true)
        }
    }

    func markAsUnread(_ articleID: UUID) {
        if let i = articles.firstIndex(where: { $0.id == articleID }) {
            articles[i].isRead = false
            // Note: isRead in ArticleState is monotonic for sync purposes.
            // We update the in-memory state but do NOT flip ArticleState.isRead to false.
            // This prevents a locally un-read article from un-reading it on another device.
        }
    }

    /// Dissolves the cluster containing the given article, making every member
    /// appear as a standalone card. Transient — the next `refreshAllFeeds()`
    /// will re-cluster everything. Intentionally does NOT rewrite the JSON cache.
    func splitCluster(for articleID: UUID) {
        guard let i = articles.firstIndex(where: { $0.id == articleID }),
              let clusterID = articles[i].clusterID else { return }
        for j in articles.indices where articles[j].clusterID == clusterID {
            articles[j].clusterID = nil
            articles[j].clusterSize = 1
            articles[j].isCanonical = true
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

    /// Updates an existing folder's name, icon, or color.
    @MainActor
    func updateFolder(id: UUID, name: String? = nil, iconName: String? = nil, colorHex: String? = nil) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FolderModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let folder = try context.fetch(descriptor).first {
            if let name   { folder.name     = name }
            if let iconName { folder.iconName = iconName }
            if let colorHex { folder.colorHex = colorHex }
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
        NotificationCenter.default.post(name: .feedAdded, object: nil)
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

    /// Sets the per-feed "prefer unique stories" toggle.
    @MainActor
    func setPreferUniqueStories(feedID: UUID, value: Bool) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == feedID }
        )
        if let feed = try context.fetch(descriptor).first {
            feed.preferUniqueStories = value
            try context.save()
            loadFromSwiftData()
        }
    }

    /// Adds or removes a YouTube content-type kind from the feed's hidden set.
    @MainActor
    func setHiddenYouTubeKind(
        feedID: UUID,
        kind: YouTubeService.YouTubeContentKind,
        hidden: Bool
    ) throws {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.id == feedID }
        )
        if let feed = try context.fetch(descriptor).first {
            var kinds = feed.hiddenYouTubeKinds
            if hidden {
                kinds.insert(kind)
            } else {
                kinds.remove(kind)
            }
            feed.hiddenYouTubeKinds = kinds
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
        upsertArticleState(articleURL: articles[index].articleURL, isPaywalled: true)
    }

    // MARK: - OPML Helpers

    /// Returns all FeedModels that have no folder assigned.
    @MainActor
    func unfiledFeedModels() -> [FeedModel] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<FeedModel>(
            predicate: #Predicate { $0.folder == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Returns all FolderModels currently persisted.
    @MainActor
    func allFolderModels() -> [FolderModel] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<FolderModel>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
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

                    let published = p.publicationDate ?? Date()
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
                        audioURL: p.audioURL,
                        articleURL: linkKey.isEmpty ? "https://example.com" : linkKey,
                        publishedAt: published,
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
            // Cluster related articles before displaying
            ArticleClusteringService.shared.clusterArticles(&newArticles)
            self.articles = newArticles
            // Persist to the local JSON cache so the next launch is pre-populated.
            ArticleCacheStore.save(newArticles)
        } else {
            // 0 articles fetched; keep existing articles
        }
    }

    // MARK: - Pipeline Sync

    /// Updates the in-memory articles array from pipeline FeedItems without re-fetching feeds.
    /// Called by RiverViewModel after a pipeline cycle to keep legacy views in sync.
    ///
    /// This is ADDITIVE — existing articles outside the pipeline set are preserved
    /// up to the 30-day retention window. RSS feeds only expose ~10-20 recent items
    /// per refresh; replacing rather than merging would silently drop the history.
    @MainActor
    func syncArticles(_ pipelineArticles: [Article]) {
        guard !pipelineArticles.isEmpty else { return }

        // Build lookup maps for in-memory read/bookmark state and ArticleState
        let existingByURL = Dictionary(
            articles.map { ($0.articleURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Apply read/bookmark state to incoming pipeline articles
        let updatedPipeline: [Article] = pipelineArticles.map { article in
            var updated = article
            if let mem = existingByURL[article.articleURL] {
                updated.isRead = mem.isRead
                updated.isBookmarked = mem.isBookmarked
            } else if let state = fetchArticleState(for: article.articleURL) {
                updated.isRead = state.isRead
                updated.isBookmarked = state.isBookmarked
                updated.isPaywalled = state.isPaywalled
            }
            return updated
        }

        // Preserve existing articles that the pipeline didn't return (older history).
        // This keeps source/folder views showing the full 30-day window even when
        // RSS feeds only expose their 10-20 most recent items.
        let pipelineURLs = Set(updatedPipeline.map(\.articleURL))
        let preserved = articles.filter { !pipelineURLs.contains($0.articleURL) }

        // Merge and drop anything older than the retention window
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -CachePolicy.cacheRetentionDays, to: Date()
        ) ?? Date()

        let merged = (updatedPipeline + preserved)
            .filter { $0.publishedAt >= cutoff || $0.isBookmarked }  // never evict saved articles
            .sorted { $0.publishedAt > $1.publishedAt }

        self.articles = merged
        ArticleCacheStore.save(merged)
    }

    // MARK: - Cache Maintenance

    /// Purges extracted articles from the SwiftData cache that are older than `days` days.
    @MainActor
    func purgeOldArticleCache(olderThan days: Int = 7) {
        guard let context = modelContext else { return }
        let service = ArticleCacheService(context: context)
        try? service.purgeOldCache(olderThan: days)
    }

    /// Clears all caches: the JSON article cache, all SwiftData CachedArticle records,
    /// and the shared URL response cache used for images.
    @MainActor
    func clearAllCaches() {
        // 1. JSON file cache
        ArticleCacheStore.clear()

        // 2. SwiftData extracted-article cache (all records)
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedArticle>()
            if let all = try? context.fetch(descriptor) {
                for record in all { context.delete(record) }
                try? context.save()
            }
        }

        // 3. URL response cache (images, web assets)
        URLCache.shared.removeAllCachedResponses()
    }

    /// Returns the combined on-disk size of all caches in bytes.
    func cacheSize() -> Int64 {
        var total = Int64(URLCache.shared.currentDiskUsage)

        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]

        if let enumerator = FileManager.default.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(size)
            }
        }

        return total
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

    // MARK: - ArticleState Persistence

    /// Upserts an ArticleState record for the given article URL.
    /// Pass only the flags you want to update; nil values are left unchanged.
    @MainActor
    private func upsertArticleState(
        articleURL: String,
        isRead: Bool? = nil,
        isBookmarked: Bool? = nil,
        isPaywalled: Bool? = nil
    ) {
        guard let context = modelContext else { return }
        let hash = ArticleState.hash(articleURL)

        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLHash == hash }
        )

        let state: ArticleState
        if let existing = try? context.fetch(descriptor).first {
            state = existing
        } else {
            state = ArticleState(articleURL: articleURL)
            context.insert(state)
        }

        // isRead is monotonic — only ever set to true, never back to false
        if let isRead, isRead == true { state.isRead = true }
        if let isBookmarked { state.isBookmarked = isBookmarked }
        if let isPaywalled { state.isPaywalled = isPaywalled }
        state.lastModifiedAt = Date()

        try? context.save()
    }

    /// Fetches the ArticleState for a given article URL, or nil if not found.
    @MainActor
    private func fetchArticleState(for articleURL: String) -> ArticleState? {
        guard let context = modelContext else { return nil }
        let hash = ArticleState.hash(articleURL)
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLHash == hash }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - UserPreferences

    /// Returns the singleton UserPreferences record, creating it if needed.
    @MainActor
    func userPreferences() -> UserPreferences {
        guard let context = modelContext else { return UserPreferences() }
        let descriptor = FetchDescriptor<UserPreferences>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        try? context.save()
        return prefs
    }

    /// Updates UserProfile.lastSyncedAt after a successful CloudKit export.
    @MainActor
    func updateProfileSyncDate() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? context.fetch(descriptor).first {
            profile.lastSyncedAt = Date()
            try? context.save()
        }
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
            id:                  model.id,
            name:                model.title,
            feedURL:             model.feedURL,
            websiteURL:          model.websiteURL,
            icon:                "dot.radiowaves.left.and.right",
            iconColor:           .blue,
            categoryID:          model.folder?.id ?? SwiftDataService.unfiledFolderID,
            isEnabled:           model.isEnabled,
            isPaywalled:         model.isPaywalled,
            addedAt:             model.addedAt,
            decayOverride:       model.decayOverride,
            preferUniqueStories: model.preferUniqueStories,
            hiddenYouTubeKinds:  model.hiddenYouTubeKinds
        )
    }
}
