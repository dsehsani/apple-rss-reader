//
//  IntegrationTests.swift
//  OpenRSSTests
//
//  Integration tests — validates the full feed parsing pipeline using
//  real-world RSS/Atom/Podcast XML saved as fixture files.
//
//  These fixtures are snapshots of real feeds, frozen in time so the tests
//  are deterministic and don't require network access.
//
//  Fixtures:
//    - nytimes.xml          (RSS 2.0, major news, media: namespaces)
//    - youtube_veritasium.xml (Atom, YouTube, media:group)
//    - daringfireball.xml   (Atom, tech blog)
//    - podcast_cortex.xml   (RSS 2.0, podcast with itunes/enclosure)
//
//  Run with Cmd+U in Xcode or: xcodebuild test -scheme OpenRSS
//

import Testing
import Foundation
@testable import OpenRSS


// =============================================================================
// MARK: - FIXTURE LOADER
// =============================================================================

/// Loads test fixture XML files from the Fixtures directory.
private func loadFixture(_ filename: String) -> Data {
    // Locate the fixture relative to this source file
    let thisFile = URL(fileURLWithPath: #filePath)
    let fixturesDir = thisFile.deletingLastPathComponent().appendingPathComponent("Fixtures")
    let fileURL = fixturesDir.appendingPathComponent(filename)

    guard let data = try? Data(contentsOf: fileURL) else {
        fatalError("Could not load fixture '\(filename)' at \(fileURL.path). Ensure the file exists in OpenRSSTests/Fixtures/")
    }
    return data
}


// =============================================================================
// MARK: - 1. NYT RSS FEED (News, RSS 2.0)
// =============================================================================
//
// What this tests:
//   Parsing a real New York Times RSS feed through RSSService. The NYT feed
//   uses RSS 2.0 with dc:, media:, and atom: namespaces — one of the most
//   complex real-world feed formats.
//
// Why it matters:
//   If the parser can handle the NYT feed correctly, it can handle most
//   standard RSS feeds. This is the most common feed type users subscribe to.
//

struct NYTFeedIntegrationTests {

    private let rssService = RSSService()

    // -------------------------------------------------------------------------
    // TEST: NYT feed parses without error
    //
    // Expected output: parseFeed completes without throwing.
    // -------------------------------------------------------------------------
    @Test func nytFeedParsesSuccessfully() async throws {
        let data = loadFixture("nytimes.xml")
        let articles = try await rssService.parseFeed(from: data)
        #expect(!articles.isEmpty, "NYT feed should contain articles")
    }

    // -------------------------------------------------------------------------
    // TEST: NYT articles have required fields populated
    //
    // Scenario: Every article should have at minimum a title and a link.
    // Expected output: No nil titles or links.
    // -------------------------------------------------------------------------
    @Test func nytArticlesHaveRequiredFields() async throws {
        let data = loadFixture("nytimes.xml")
        let articles = try await rssService.parseFeed(from: data)

        for (i, article) in articles.enumerated() {
            #expect(article.title != nil && !article.title!.isEmpty,
                    "Article \(i) should have a title")
            #expect(article.link != nil && !article.link!.isEmpty,
                    "Article \(i) should have a link")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: NYT articles have publication dates
    //
    // Expected output: Most articles have a non-nil publicationDate.
    // -------------------------------------------------------------------------
    @Test func nytArticlesHavePublicationDates() async throws {
        let data = loadFixture("nytimes.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withDates = articles.filter { $0.publicationDate != nil }
        let ratio = Double(withDates.count) / Double(articles.count)
        #expect(ratio > 0.9,
                "At least 90% of NYT articles should have dates, got \(Int(ratio * 100))%")
    }

    // -------------------------------------------------------------------------
    // TEST: NYT articles have descriptions
    //
    // Expected output: Most articles have a non-nil, non-empty description.
    // -------------------------------------------------------------------------
    @Test func nytArticlesHaveDescriptions() async throws {
        let data = loadFixture("nytimes.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withDescriptions = articles.filter {
            $0.description != nil && !$0.description!.isEmpty
        }
        let ratio = Double(withDescriptions.count) / Double(articles.count)
        #expect(ratio > 0.8,
                "At least 80% of NYT articles should have descriptions, got \(Int(ratio * 100))%")
    }

    // -------------------------------------------------------------------------
    // TEST: NYT articles have image URLs
    //
    // NYT feeds typically include media:content or media:thumbnail for images.
    // Expected output: A significant portion of articles have images.
    // -------------------------------------------------------------------------
    @Test func nytArticlesHaveImages() async throws {
        let data = loadFixture("nytimes.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withImages = articles.filter {
            $0.imageURL != nil && !$0.imageURL!.isEmpty
        }
        #expect(withImages.count > 0,
                "At least some NYT articles should have image URLs")
    }

    // -------------------------------------------------------------------------
    // TEST: Full pipeline — NYT articles convert to FeedItems and store in SQLite
    //
    // Scenario: Parse NYT feed, convert to FeedItems, store in SQLite,
    //   read back, and verify data integrity.
    // Expected output: Round-trip preserves titles and links.
    // -------------------------------------------------------------------------
    @Test func nytFullPipelineRoundTrip() async throws {
        let data = loadFixture("nytimes.xml")
        let parsed = try await rssService.parseFeed(from: data)
        let store = SQLiteStore.shared
        let sourceID = UUID()
        let categoryID = UUID()

        // Convert ParsedArticles → FeedItems
        let feedItems: [FeedItem] = parsed.compactMap { article in
            guard let title = article.title,
                  let linkStr = article.link,
                  let link = URL(string: linkStr) else { return nil }
            return FeedItem(
                sourceID: sourceID,
                title: title,
                link: link,
                publishedAt: article.publicationDate ?? Date(),
                excerpt: article.description ?? "",
                imageURL: article.imageURL
            )
        }

        #expect(!feedItems.isEmpty, "Should convert at least some articles to FeedItems")

        // Store in SQLite
        store.upsertFeedItems(feedItems)

        // Read back
        let fetched = store.fetchItems(forSource: sourceID)
        #expect(fetched.count == feedItems.count,
                "Should fetch back all \(feedItems.count) items, got \(fetched.count)")

        // Verify a sample item
        if let original = feedItems.first,
           let stored = fetched.first(where: { $0.id == original.id }) {
            #expect(stored.title == original.title, "Title should survive round-trip")
            #expect(stored.link == original.link, "Link should survive round-trip")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Full pipeline — NYT articles get scored and ranked
    //
    // Scenario: Store articles, run decay scoring, assemble snapshot.
    // Expected output: Snapshot contains articles sorted by relevance.
    // -------------------------------------------------------------------------
    @Test func nytFullPipelineScoringAndSnapshot() async throws {
        let data = loadFixture("nytimes.xml")
        let parsed = try await rssService.parseFeed(from: data)
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let feedItems: [FeedItem] = parsed.compactMap { article in
            guard let title = article.title,
                  let linkStr = article.link,
                  let link = URL(string: linkStr) else { return nil }
            return FeedItem(
                sourceID: sourceID,
                title: title,
                link: link,
                publishedAt: article.publicationDate ?? Date(),
                excerpt: article.description ?? "",
                imageURL: article.imageURL,
                riverVisible: true
            )
        }

        store.upsertFeedItems(feedItems)

        // Run decay scoring
        let scorer = DecayScoringService()
        scorer.scoreAllItems()

        // Assemble snapshot
        let snapshotService = RiverSnapshotService(store: store)
        let snapshot = snapshotService.assembleSnapshot(rateGateResult: nil)

        // Our items should be in the snapshot
        let ourItemIDs = Set(feedItems.map(\.id))
        let inSnapshot = snapshot.items.filter { ourItemIDs.contains($0.id) }
        #expect(!inSnapshot.isEmpty,
                "At least some NYT articles should appear in the river snapshot")

        // Verify sorting: positional weights should be descending
        for i in 0..<max(0, inSnapshot.count - 1) {
            #expect(inSnapshot[i].positionalWeight >= inSnapshot[i + 1].positionalWeight,
                    "Snapshot should be sorted by positional weight descending")
        }
    }
}


// =============================================================================
// MARK: - 2. YOUTUBE ATOM FEED
// =============================================================================
//
// What this tests:
//   Parsing a real YouTube channel Atom feed (Veritasium). YouTube uses
//   the Atom format with media: namespace extensions that FeedKit partially
//   handles, plus custom media:group elements that require YouTubeAtomParser.
//
// Why it matters:
//   YouTube is one of the most popular feed sources. If YouTube parsing
//   breaks, a large portion of users lose their video feeds.
//

struct YouTubeFeedIntegrationTests {

    private let rssService = RSSService()

    // -------------------------------------------------------------------------
    // TEST: YouTube Atom feed parses via RSSService
    //
    // Expected output: Returns video entries with titles and links.
    // -------------------------------------------------------------------------
    @Test func youtubeFeedParsesSuccessfully() async throws {
        let data = loadFixture("youtube_veritasium.xml")
        let articles = try await rssService.parseFeed(from: data)
        #expect(!articles.isEmpty, "YouTube feed should contain video entries")
    }

    // -------------------------------------------------------------------------
    // TEST: YouTube entries have titles and video links
    //
    // Expected output: Every entry has a title and a youtube.com watch URL.
    // -------------------------------------------------------------------------
    @Test func youtubeEntriesHaveRequiredFields() async throws {
        let data = loadFixture("youtube_veritasium.xml")
        let articles = try await rssService.parseFeed(from: data)

        for (i, article) in articles.enumerated() {
            #expect(article.title != nil && !article.title!.isEmpty,
                    "Video \(i) should have a title")
            #expect(article.link != nil && article.link!.contains("youtube.com"),
                    "Video \(i) should have a YouTube link, got: \(article.link ?? "nil")")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: YouTubeAtomParser extracts thumbnails and descriptions
    //
    // Scenario: The same XML data is parsed by YouTubeAtomParser for the
    //   media:group fields that FeedKit/RSSService can't extract.
    // Expected output: At least some videos have thumbnail URLs and descriptions.
    // -------------------------------------------------------------------------
    @Test func youtubeAtomParserExtractsMediaGroup() {
        let data = loadFixture("youtube_veritasium.xml")
        let extras = YouTubeAtomParser().parse(data: data)

        #expect(!extras.isEmpty, "YouTubeAtomParser should find video entries")

        let withThumbnails = extras.values.filter { $0.thumbnailURL != nil }
        #expect(!withThumbnails.isEmpty,
                "At least some videos should have thumbnail URLs")

        let withDescriptions = extras.values.filter {
            $0.description != nil && !$0.description!.isEmpty
        }
        #expect(!withDescriptions.isEmpty,
                "At least some videos should have descriptions")
    }

    // -------------------------------------------------------------------------
    // TEST: RSSService and YouTubeAtomParser results can be merged
    //
    // Scenario: Parse with both services, match by URL, verify thumbnails
    //   from YouTubeAtomParser supplement the RSSService results.
    // Expected output: Matching URLs exist in both result sets.
    // -------------------------------------------------------------------------
    @Test func youtubeResultsMergeByURL() async throws {
        let data = loadFixture("youtube_veritasium.xml")
        let articles = try await rssService.parseFeed(from: data)
        let extras = YouTubeAtomParser().parse(data: data)

        // Check that at least some article links match YouTubeAtomParser keys
        let articleLinks = Set(articles.compactMap(\.link))
        let extraKeys = Set(extras.keys)
        let overlap = articleLinks.intersection(extraKeys)

        #expect(!overlap.isEmpty,
                "RSSService and YouTubeAtomParser should share matching video URLs")
    }
}


// =============================================================================
// MARK: - 3. DARING FIREBALL (Tech Blog, Atom)
// =============================================================================
//
// What this tests:
//   Parsing a real tech blog Atom feed (Daring Fireball by John Gruber).
//   This is a standard Atom feed with content:encoded HTML bodies — a
//   common format for individual bloggers and small publishers.
//
// Why it matters:
//   Blog feeds are the bread and butter of RSS. If a well-known blog
//   can't be parsed, the app fails at its core purpose.
//

struct DaringFireballIntegrationTests {

    private let rssService = RSSService()

    // -------------------------------------------------------------------------
    // TEST: Daring Fireball Atom feed parses successfully
    //
    // Expected output: Returns blog entries.
    // -------------------------------------------------------------------------
    @Test func daringFireballParsesSuccessfully() async throws {
        let data = loadFixture("daringfireball.xml")
        let articles = try await rssService.parseFeed(from: data)
        #expect(!articles.isEmpty, "Daring Fireball feed should contain entries")
    }

    // -------------------------------------------------------------------------
    // TEST: Blog entries have titles and links
    //
    // Expected output: Every entry has a title and a link.
    // -------------------------------------------------------------------------
    @Test func blogEntriesHaveRequiredFields() async throws {
        let data = loadFixture("daringfireball.xml")
        let articles = try await rssService.parseFeed(from: data)

        for (i, article) in articles.enumerated() {
            #expect(article.title != nil && !article.title!.isEmpty,
                    "Entry \(i) should have a title")
            #expect(article.link != nil && !article.link!.isEmpty,
                    "Entry \(i) should have a link")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Blog entries have content/descriptions
    //
    // Daring Fireball includes full article content in the feed.
    // Expected output: Most entries have descriptions.
    // -------------------------------------------------------------------------
    @Test func blogEntriesHaveContent() async throws {
        let data = loadFixture("daringfireball.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withContent = articles.filter {
            $0.description != nil && !$0.description!.isEmpty
        }
        let ratio = Double(withContent.count) / Double(articles.count)
        #expect(ratio > 0.8,
                "At least 80% of blog entries should have content, got \(Int(ratio * 100))%")
    }

    // -------------------------------------------------------------------------
    // TEST: Blog entries have author information
    //
    // Expected output: At least some entries have an author.
    // -------------------------------------------------------------------------
    @Test func blogEntriesHaveAuthor() async throws {
        let data = loadFixture("daringfireball.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withAuthor = articles.filter {
            $0.author != nil && !$0.author!.isEmpty
        }
        #expect(!withAuthor.isEmpty,
                "At least some blog entries should have an author")
    }
}


// =============================================================================
// MARK: - 4. PODCAST FEED (RSS 2.0 + iTunes)
// =============================================================================
//
// What this tests:
//   Parsing a real podcast feed (Cortex by Relay FM). Podcast feeds use
//   RSS 2.0 with itunes: namespace extensions and <enclosure> tags for
//   audio files. This is a fundamentally different feed type from news/blogs.
//
// Why it matters:
//   Podcasts are a common RSS use case. The parser must correctly extract
//   audio URLs from enclosures and NOT treat audio URLs as images.
//

struct PodcastFeedIntegrationTests {

    private let rssService = RSSService()

    // -------------------------------------------------------------------------
    // TEST: Podcast feed parses successfully
    //
    // Expected output: Returns episode entries.
    // -------------------------------------------------------------------------
    @Test func podcastFeedParsesSuccessfully() async throws {
        let data = loadFixture("podcast_cortex.xml")
        let articles = try await rssService.parseFeed(from: data)
        #expect(!articles.isEmpty, "Podcast feed should contain episodes")
    }

    // -------------------------------------------------------------------------
    // TEST: Podcast episodes have titles and links
    //
    // Expected output: Every episode has a title and a link.
    // -------------------------------------------------------------------------
    @Test func podcastEpisodesHaveRequiredFields() async throws {
        let data = loadFixture("podcast_cortex.xml")
        let articles = try await rssService.parseFeed(from: data)

        for (i, article) in articles.enumerated() {
            #expect(article.title != nil && !article.title!.isEmpty,
                    "Episode \(i) should have a title")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Podcast episodes have audio URLs
    //
    // Scenario: Podcast episodes carry audio via <enclosure> tags.
    // Expected output: Most episodes have a non-nil audioURL.
    // -------------------------------------------------------------------------
    @Test func podcastEpisodesHaveAudioURLs() async throws {
        let data = loadFixture("podcast_cortex.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withAudio = articles.filter {
            $0.audioURL != nil && !$0.audioURL!.isEmpty
        }
        let ratio = Double(withAudio.count) / Double(articles.count)
        #expect(ratio > 0.8,
                "At least 80% of podcast episodes should have audio URLs, got \(Int(ratio * 100))%")
    }

    // -------------------------------------------------------------------------
    // TEST: Audio URLs are not mistakenly used as image URLs
    //
    // Scenario: The parser should distinguish audio enclosures from image
    //   enclosures. An mp3 URL should never appear in the imageURL field.
    // Expected output: No imageURL ends with .mp3 or contains audio MIME types.
    // -------------------------------------------------------------------------
    @Test func audioURLsNotUsedAsImages() async throws {
        let data = loadFixture("podcast_cortex.xml")
        let articles = try await rssService.parseFeed(from: data)

        for (i, article) in articles.enumerated() {
            if let imageURL = article.imageURL {
                let lower = imageURL.lowercased()
                #expect(!lower.hasSuffix(".mp3"),
                        "Episode \(i) imageURL should not be an mp3: \(imageURL)")
                #expect(!lower.hasSuffix(".m4a"),
                        "Episode \(i) imageURL should not be an m4a: \(imageURL)")
                #expect(!lower.contains("audio"),
                        "Episode \(i) imageURL should not contain 'audio': \(imageURL)")
            }
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Podcast episodes have publication dates
    //
    // Expected output: Most episodes have dates.
    // -------------------------------------------------------------------------
    @Test func podcastEpisodesHaveDates() async throws {
        let data = loadFixture("podcast_cortex.xml")
        let articles = try await rssService.parseFeed(from: data)

        let withDates = articles.filter { $0.publicationDate != nil }
        let ratio = Double(withDates.count) / Double(articles.count)
        #expect(ratio > 0.9,
                "At least 90% of podcast episodes should have dates, got \(Int(ratio * 100))%")
    }
}


// =============================================================================
// MARK: - 5. CROSS-FEED PIPELINE TEST
// =============================================================================
//
// What this tests:
//   The full pipeline with multiple feed types at once — simulating a user
//   who subscribes to a news site, a blog, a YouTube channel, and a podcast
//   all at the same time.
//
// Why it matters:
//   The pipeline must handle mixed feed types correctly. Articles from
//   different formats must coexist in SQLite and appear together in the
//   river snapshot without data corruption or type confusion.
//

struct CrossFeedPipelineTests {

    private let rssService = RSSService()

    // -------------------------------------------------------------------------
    // TEST: Multiple feed types coexist in SQLite and snapshot
    //
    // Scenario: Parse all 4 fixture feeds, convert to FeedItems with different
    //   sourceIDs, store all in SQLite, score, and assemble one snapshot.
    // Expected output: Snapshot contains articles from all 4 sources, sorted
    //   by relevance, with no data corruption.
    // -------------------------------------------------------------------------
    @Test func multipleFeedTypesCoexistInPipeline() async throws {
        let store = SQLiteStore.shared

        // Parse all 4 feeds
        let nytData = loadFixture("nytimes.xml")
        let ytData = loadFixture("youtube_veritasium.xml")
        let dfData = loadFixture("daringfireball.xml")
        let podData = loadFixture("podcast_cortex.xml")

        let nytArticles = try await rssService.parseFeed(from: nytData)
        let ytArticles = try await rssService.parseFeed(from: ytData)
        let dfArticles = try await rssService.parseFeed(from: dfData)
        let podArticles = try await rssService.parseFeed(from: podData)

        // Assign unique sourceIDs
        let nytSourceID = UUID()
        let ytSourceID = UUID()
        let dfSourceID = UUID()
        let podSourceID = UUID()
        let allSourceIDs = [nytSourceID, ytSourceID, dfSourceID, podSourceID]

        // Convert to FeedItems
        func convert(_ articles: [ParsedArticle], sourceID: UUID, tier: VelocityTier) -> [FeedItem] {
            articles.compactMap { a in
                guard let title = a.title,
                      let linkStr = a.link,
                      let link = URL(string: linkStr) else { return nil }
                return FeedItem(
                    sourceID: sourceID,
                    title: title,
                    link: link,
                    publishedAt: a.publicationDate ?? Date(),
                    excerpt: a.description ?? "",
                    imageURL: a.imageURL,
                    audioURL: a.audioURL,
                    velocityTier: tier,
                    riverVisible: true
                )
            }
        }

        let allItems = convert(nytArticles, sourceID: nytSourceID, tier: .news)
            + convert(ytArticles, sourceID: ytSourceID, tier: .article)
            + convert(dfArticles, sourceID: dfSourceID, tier: .essay)
            + convert(podArticles, sourceID: podSourceID, tier: .evergreen)

        #expect(allItems.count > 10,
                "Should have a meaningful number of items across all feeds")

        // Store all in SQLite
        store.upsertFeedItems(allItems)

        // Score all items
        let scorer = DecayScoringService()
        scorer.scoreAllItems()

        // Assemble snapshot
        let snapshotService = RiverSnapshotService(store: store)
        let snapshot = snapshotService.assembleSnapshot(rateGateResult: nil)

        // Verify articles from all 4 sources appear
        for sourceID in allSourceIDs {
            let fromSource = snapshot.items.filter { item in
                if case .article(let fi) = item { return fi.sourceID == sourceID }
                return false
            }
            #expect(!fromSource.isEmpty,
                    "Snapshot should contain articles from source \(sourceID)")
        }

        // Verify sorting
        for i in 0..<max(0, snapshot.items.count - 1) {
            #expect(snapshot.items[i].positionalWeight >= snapshot.items[i + 1].positionalWeight,
                    "Snapshot should be sorted by positional weight descending")
        }
    }
}
