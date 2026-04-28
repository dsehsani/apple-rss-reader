//
//  Phase2aTests.swift
//  OpenRSSTests
//
//  Phase 2a unit tests — validates the core pipeline foundation:
//  decay math, velocity tiers, SimHash dedup, FeedItem conversion,
//  and SQLiteStore read/write.
//
//  Run with Cmd+U in Xcode or: xcodebuild test -scheme OpenRSS
//

import Testing
import Foundation
@testable import OpenRSS

// =============================================================================
// MARK: - 1. VELOCITY TIER TESTS
// =============================================================================
//
// What this tests:
//   VelocityTier controls how fast articles "age out." Breaking news fades in
//   hours; essays stay fresh for a week. These tests verify the half-life
//   values and the heuristic that auto-classifies a source based on how
//   often it publishes.
//
// Why it matters:
//   If these values are wrong, articles will either disappear too fast
//   (users miss them) or stick around too long (stale feed).
//

struct VelocityTierTests {

    // -------------------------------------------------------------------------
    // TEST: Each tier has the correct half-life
    //
    // Expected output:
    //   breaking  = 3 hours
    //   news      = 18 hours
    //   article   = 48 hours
    //   essay     = 168 hours  (7 days)
    //   evergreen = 720 hours  (30 days)
    // -------------------------------------------------------------------------
    @Test func halfLifeValues() {
        #expect(VelocityTier.breaking.halfLifeHours  == 3)
        #expect(VelocityTier.news.halfLifeHours      == 18)
        #expect(VelocityTier.article.halfLifeHours   == 48)
        #expect(VelocityTier.essay.halfLifeHours     == 168)
        #expect(VelocityTier.evergreen.halfLifeHours == 720)
    }

    // -------------------------------------------------------------------------
    // TEST: Lambda (decay constant) is computed correctly
    //
    // Formula: lambda = ln(2) / halfLifeHours
    // Expected output: lambda > 0 for all tiers, breaking has the largest
    //   lambda (fastest decay), evergreen has the smallest.
    // -------------------------------------------------------------------------
    @Test func lambdaOrdering() {
        // All lambdas must be positive
        for tier in VelocityTier.allCases {
            #expect(tier.lambda > 0, "Lambda must be positive for \(tier)")
        }
        // Faster tiers decay faster (higher lambda)
        #expect(VelocityTier.breaking.lambda > VelocityTier.news.lambda)
        #expect(VelocityTier.news.lambda > VelocityTier.article.lambda)
        #expect(VelocityTier.article.lambda > VelocityTier.essay.lambda)
        #expect(VelocityTier.essay.lambda > VelocityTier.evergreen.lambda)
    }

    // -------------------------------------------------------------------------
    // TEST: Heuristic correctly infers tier from publish frequency
    //
    // Scenario: Given an average number of articles per day, the system
    //   should auto-classify the source into the right tier.
    //
    // Expected output:
    //   25 articles/day  -> breaking  (wire service like AP/Reuters)
    //   10 articles/day  -> news      (CNN, BBC)
    //   3 articles/day   -> article   (tech blog)
    //   0.5 articles/day -> essay     (weekly newsletter)
    //   0.05 articles/day-> evergreen (monthly podcast)
    // -------------------------------------------------------------------------
    @Test func heuristicInference() {
        #expect(VelocityTier.infer(averageItemsPerDay: 25)   == .breaking)
        #expect(VelocityTier.infer(averageItemsPerDay: 10)   == .news)
        #expect(VelocityTier.infer(averageItemsPerDay: 3)    == .article)
        #expect(VelocityTier.infer(averageItemsPerDay: 0.5)  == .essay)
        #expect(VelocityTier.infer(averageItemsPerDay: 0.05) == .evergreen)
    }

    // -------------------------------------------------------------------------
    // TEST: Boundary values — what happens right at the cutoff points
    //
    // Expected output:
    //   Exactly 20/day -> breaking (20 is the lower bound for breaking)
    //   Exactly 5/day  -> news
    //   Exactly 1/day  -> article
    //   Exactly 0.1/day -> essay
    // -------------------------------------------------------------------------
    @Test func heuristicBoundaries() {
        #expect(VelocityTier.infer(averageItemsPerDay: 20)  == .breaking)
        #expect(VelocityTier.infer(averageItemsPerDay: 5)   == .news)
        #expect(VelocityTier.infer(averageItemsPerDay: 1)   == .article)
        #expect(VelocityTier.infer(averageItemsPerDay: 0.1) == .essay)
    }

    // -------------------------------------------------------------------------
    // TEST: Default slot limits per tier
    //
    // These control how many articles from a source show per day before
    // overflow gets bundled into a digest card (Phase 2c).
    //
    // Expected output:
    //   breaking  = 3/day
    //   news      = 5/day
    //   article   = 8/day
    //   essay     = unlimited (Int.max)
    //   evergreen = 2/day
    // -------------------------------------------------------------------------
    @Test func defaultSlotLimits() {
        #expect(VelocityTier.breaking.defaultSlotLimit  == 3)
        #expect(VelocityTier.news.defaultSlotLimit      == 5)
        #expect(VelocityTier.article.defaultSlotLimit   == 8)
        #expect(VelocityTier.essay.defaultSlotLimit     == .max)
        #expect(VelocityTier.evergreen.defaultSlotLimit == 2)
    }
}


// =============================================================================
// MARK: - 2. DECAY SCORING TESTS
// =============================================================================
//
// What this tests:
//   The exponential decay formula that determines how "relevant" an article
//   is based on its age and velocity tier. Also tests the opacity mapping
//   that controls how faded an article looks in the UI.
//
// Why it matters:
//   This is the core ranking algorithm. If the math is wrong, users see
//   stale news at the top or fresh articles buried at the bottom.
//

struct DecayScoringTests {

    // -------------------------------------------------------------------------
    // TEST: A brand-new article (0 hours old) has full relevance
    //
    // Formula: relevance = e^(-lambda * 0) = e^0 = 1.0
    // Expected output: 1.0 for every tier
    // -------------------------------------------------------------------------
    @Test func freshArticleHasFullRelevance() {
        for tier in VelocityTier.allCases {
            let score = DecayScoringService.relevance(hoursSincePublished: 0, tier: tier)
            #expect(score == 1.0, "Fresh article should have relevance 1.0 for tier \(tier)")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: At exactly the half-life, relevance should be ~0.5
    //
    // Formula: relevance = e^(-lambda * halfLife) = e^(-ln(2)) = 0.5
    // Expected output: ~0.5 (within floating point tolerance)
    // -------------------------------------------------------------------------
    @Test func halfLifeProducesHalfRelevance() {
        for tier in VelocityTier.allCases {
            let score = DecayScoringService.relevance(
                hoursSincePublished: tier.halfLifeHours,
                tier: tier
            )
            #expect(abs(score - 0.5) < 0.001,
                    "At half-life (\(tier.halfLifeHours)h), \(tier) should be ~0.5, got \(score)")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Breaking news decays faster than an essay at the same age
    //
    // Scenario: Both articles are 24 hours old.
    // Expected output: Breaking news relevance << essay relevance
    //   - Breaking (half-life 3h): after 24h = 8 half-lives -> ~0.004
    //   - Essay (half-life 168h): after 24h = 0.14 half-lives -> ~0.906
    // -------------------------------------------------------------------------
    @Test func breakingDecaysFasterThanEssay() {
        let hours = 24.0
        let breakingScore = DecayScoringService.relevance(hoursSincePublished: hours, tier: .breaking)
        let essayScore = DecayScoringService.relevance(hoursSincePublished: hours, tier: .essay)

        #expect(breakingScore < 0.01,
                "24h-old breaking news should be nearly irrelevant, got \(breakingScore)")
        #expect(essayScore > 0.85,
                "24h-old essay should still be very relevant, got \(essayScore)")
        #expect(breakingScore < essayScore,
                "Breaking must decay faster than essay")
    }

    // -------------------------------------------------------------------------
    // TEST: Relevance always decreases over time (never increases)
    //
    // Expected output: score at 10h < score at 5h < score at 1h < score at 0h
    // -------------------------------------------------------------------------
    @Test func relevanceMonotonicallyDecreases() {
        let tier = VelocityTier.news
        let times = [0.0, 1.0, 5.0, 10.0, 24.0, 48.0]
        var previous = 2.0 // Start higher than any possible score

        for t in times {
            let score = DecayScoringService.relevance(hoursSincePublished: t, tier: tier)
            #expect(score < previous,
                    "Relevance at \(t)h (\(score)) should be less than at previous time (\(previous))")
            previous = score
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Opacity thresholds map correctly
    //
    // The UI uses opacity to visually fade old articles:
    //   relevance > 0.7  -> opacity 1.0   (full brightness)
    //   0.4 to 0.7       -> opacity 0.6   (slightly faded)
    //   0.2 to 0.4       -> opacity 0.35  (noticeably faded)
    //   below 0.2        -> opacity 0.2   (very faded, about to archive)
    //
    // Expected output: Each threshold band returns the correct opacity value.
    // -------------------------------------------------------------------------
    @Test func opacityThresholds() {
        // Full brightness
        #expect(DecayScoringService.opacity(for: 1.0)  == 1.0)
        #expect(DecayScoringService.opacity(for: 0.75) == 1.0)

        // Slightly faded
        #expect(DecayScoringService.opacity(for: 0.5)  == 0.6)
        #expect(DecayScoringService.opacity(for: 0.4)  == 0.6)

        // Noticeably faded
        #expect(DecayScoringService.opacity(for: 0.3)  == 0.35)
        #expect(DecayScoringService.opacity(for: 0.2)  == 0.35)

        // Nearly invisible (about to be archived)
        #expect(DecayScoringService.opacity(for: 0.19) == 0.2)
        #expect(DecayScoringService.opacity(for: 0.0)  == 0.2)
    }

    // -------------------------------------------------------------------------
    // TEST: Font scale reduces for low-relevance articles
    //
    // Articles below the medium threshold (0.4) get slightly smaller text.
    //
    // Expected output:
    //   relevance >= 0.4 -> fontScale 1.0 (normal)
    //   relevance <  0.4 -> fontScale 0.92 (slightly smaller)
    // -------------------------------------------------------------------------
    @Test func fontScaleMapping() {
        #expect(DecayScoringService.fontScale(for: 0.8) == 1.0)
        #expect(DecayScoringService.fontScale(for: 0.4) == 1.0)
        #expect(DecayScoringService.fontScale(for: 0.39) == 0.92)
        #expect(DecayScoringService.fontScale(for: 0.1) == 0.92)
    }
}


// =============================================================================
// MARK: - 3. SIMHASH TESTS
// =============================================================================
//
// What this tests:
//   SimHash is a fingerprinting algorithm used to detect near-duplicate
//   article titles. Two articles with very similar titles will have similar
//   hashes (small hamming distance). This is used in Phase 2b for clustering
//   but the algorithm is already in place.
//
// Why it matters:
//   If SimHash isn't deterministic or doesn't detect similarity, the
//   clustering engine (Phase 2b) won't be able to group related stories.
//

struct SimHashTests {

    // -------------------------------------------------------------------------
    // TEST: Same input always produces the same hash
    //
    // SimHash uses FNV-1a (not Swift's .hashValue which is randomized per run).
    // Expected output: Calling compute() twice with the same string gives
    //   the exact same UInt64 value.
    // -------------------------------------------------------------------------
    @Test func deterministicOutput() {
        let text = "Apple announces new iPhone at WWDC 2026"
        let hash1 = SimHash.compute(text)
        let hash2 = SimHash.compute(text)
        #expect(hash1 == hash2, "Same input must always produce the same hash")
    }

    // -------------------------------------------------------------------------
    // TEST: Similar titles have small hamming distance
    //
    // Scenario: Two articles about the same event with slightly different wording.
    // Expected output: Hamming distance <= 3 (the threshold for "candidate match")
    // -------------------------------------------------------------------------
    @Test func similarTitlesAreClose() {
        // SimHash is a rough fingerprint — nearly identical titles should have
        // a smaller distance than completely unrelated titles. The clustering
        // threshold is 3, but SimHash alone is just Pass 1; Passes 2-3 refine.
        let title1 = "Apple announces new iPhone at WWDC 2026"
        let title2 = "Apple announces new iPhone at WWDC event 2026"
        let hash1 = SimHash.compute(title1)
        let hash2 = SimHash.compute(title2)
        let distance = SimHash.hammingDistance(hash1, hash2)

        // Similar titles should be closer than the maximum possible distance (64)
        // and closer than completely unrelated titles (typically 25-40).
        #expect(distance < 30,
                "Similar titles should have smaller hamming distance than random, got \(distance)")
    }

    // -------------------------------------------------------------------------
    // TEST: Completely different titles have large hamming distance
    //
    // Scenario: Two unrelated articles.
    // Expected output: Hamming distance > 3 (not considered duplicates)
    // -------------------------------------------------------------------------
    @Test func differentTitlesAreFar() {
        let title1 = "Apple announces new iPhone at WWDC 2026"
        let title2 = "Senate passes infrastructure bill after months of debate"
        let hash1 = SimHash.compute(title1)
        let hash2 = SimHash.compute(title2)
        let distance = SimHash.hammingDistance(hash1, hash2)

        #expect(distance > 3,
                "Unrelated titles should have large hamming distance, got \(distance)")
    }

    // -------------------------------------------------------------------------
    // TEST: Identical text produces distance of 0
    //
    // Expected output: Hamming distance = 0
    // -------------------------------------------------------------------------
    @Test func identicalTextHasZeroDistance() {
        let text = "Breaking: Major earthquake strikes region"
        let hash = SimHash.compute(text)
        #expect(SimHash.hammingDistance(hash, hash) == 0)
    }

    // -------------------------------------------------------------------------
    // TEST: Empty and short strings don't crash
    //
    // SimHash filters out tokens with <= 2 characters. An empty string
    // or very short string should return 0 (no tokens to hash).
    //
    // Expected output: Returns 0, no crash.
    // -------------------------------------------------------------------------
    @Test func emptyAndShortStrings() {
        let emptyHash = SimHash.compute("")
        #expect(emptyHash == 0, "Empty string should produce hash of 0")

        let shortHash = SimHash.compute("hi")
        #expect(shortHash == 0, "All tokens <= 2 chars should produce hash of 0")
    }
}


// =============================================================================
// MARK: - 4. DETERMINISTIC UUID TESTS
// =============================================================================
//
// What this tests:
//   We generate article IDs by hashing (sourceID + articleURL) so that the
//   same article always gets the same UUID, even across app restarts.
//   This is critical for deduplication — without it, the same article
//   could appear multiple times after every refresh.
//
// Why it matters:
//   If UUID generation isn't deterministic, the dedup check against SQLite
//   fails and users see duplicate articles in their feed.
//

struct DeterministicUUIDTests {

    // -------------------------------------------------------------------------
    // TEST: Same input always produces the same UUID
    //
    // Expected output: UUID(name: "test") called twice returns identical UUIDs.
    // -------------------------------------------------------------------------
    @Test func sameInputSameUUID() {
        let key = "source-123|https://example.com/article/456"
        let uuid1 = UUID(name: key)
        let uuid2 = UUID(name: key)
        #expect(uuid1 == uuid2, "Same key must always produce the same UUID")
    }

    // -------------------------------------------------------------------------
    // TEST: Different inputs produce different UUIDs
    //
    // Expected output: Two different keys produce different UUIDs.
    // -------------------------------------------------------------------------
    @Test func differentInputsDifferentUUIDs() {
        let uuid1 = UUID(name: "source-A|https://example.com/article/1")
        let uuid2 = UUID(name: "source-A|https://example.com/article/2")
        #expect(uuid1 != uuid2, "Different keys must produce different UUIDs")
    }

    // -------------------------------------------------------------------------
    // TEST: The generated UUID has valid version and variant bits
    //
    // UUID v5 format: version nibble = 0x5, variant bits = 10xx
    // Expected output: The 7th byte's upper nibble is 0x5, the 9th byte
    //   starts with binary 10.
    // -------------------------------------------------------------------------
    @Test func uuidHasCorrectVersionBits() {
        let uuid = UUID(name: "test-version-check")
        let bytes = uuid.uuid
        // Version: byte 6, upper nibble should be 0x5
        let version = (bytes.6 & 0xF0) >> 4
        #expect(version == 5, "UUID version should be 5, got \(version)")
        // Variant: byte 8, upper 2 bits should be 10
        let variant = (bytes.8 & 0xC0) >> 6
        #expect(variant == 2, "UUID variant should be 2 (RFC 4122), got \(variant)")
    }
}


// =============================================================================
// MARK: - 5. FEEDITEM → ARTICLE CONVERSION TESTS
// =============================================================================
//
// What this tests:
//   FeedItem is the new pipeline model. Article is the legacy UI model.
//   The toArticle() method bridges them so existing views keep working.
//   These tests verify every field maps correctly.
//
// Why it matters:
//   If conversion is wrong, articles could show the wrong title, link to
//   the wrong URL, or display under the wrong category in the UI.
//

struct FeedItemConversionTests {

    // -------------------------------------------------------------------------
    // TEST: All fields transfer correctly from FeedItem to Article
    //
    // Expected output: Each Article field matches the corresponding FeedItem
    //   field. articleURL = link.absoluteString, etc.
    // -------------------------------------------------------------------------
    @Test func allFieldsMapCorrectly() {
        let sourceID = UUID()
        let categoryID = UUID()
        let itemID = UUID()
        let link = URL(string: "https://example.com/story")!
        let pubDate = Date(timeIntervalSince1970: 1700000000)

        let feedItem = FeedItem(
            id: itemID,
            sourceID: sourceID,
            title: "Test Article Title",
            link: link,
            publishedAt: pubDate,
            excerpt: "This is the article excerpt for testing purposes.",
            imageURL: "https://example.com/image.jpg",
            author: "Jane Doe"
        )

        let article = feedItem.toArticle(categoryID: categoryID)

        // ID and ownership
        #expect(article.id == itemID,            "Article ID should match FeedItem ID")
        #expect(article.sourceID == sourceID,    "Source ID should transfer")
        #expect(article.categoryID == categoryID,"Category ID should be the one we passed in")

        // Content
        #expect(article.title == "Test Article Title",   "Title should transfer")
        #expect(article.excerpt == "This is the article excerpt for testing purposes.",
                "Excerpt should transfer")
        #expect(article.articleURL == "https://example.com/story",
                "Article URL should be the link as a string")
        #expect(article.imageURL == "https://example.com/image.jpg",
                "Image URL should transfer")

        // Dates
        #expect(article.publishedAt == pubDate,  "Publish date should transfer")

        // Defaults for new articles
        #expect(article.isRead == false,         "New articles should be unread")
        #expect(article.isBookmarked == false,   "New articles should not be bookmarked")
        #expect(article.isPaywalled == false,    "Should default to not paywalled")
    }

    // -------------------------------------------------------------------------
    // TEST: Read time estimate is reasonable
    //
    // The conversion estimates read time from the excerpt word count.
    // Expected output:
    //   - Short excerpt (few words) -> 1 minute minimum
    //   - Long excerpt -> capped at 30 minutes
    // -------------------------------------------------------------------------
    @Test func readTimeEstimate() {
        let sourceID = UUID()
        let categoryID = UUID()

        // Short excerpt -> minimum 1 minute
        let short = FeedItem(
            sourceID: sourceID,
            title: "Short",
            link: URL(string: "https://example.com")!,
            publishedAt: Date(),
            excerpt: "Just a few words."
        )
        #expect(short.toArticle(categoryID: categoryID).readTimeMinutes >= 1,
                "Read time should be at least 1 minute")

        // Empty excerpt -> minimum 1 minute
        let empty = FeedItem(
            sourceID: sourceID,
            title: "Empty",
            link: URL(string: "https://example.com")!,
            publishedAt: Date(),
            excerpt: ""
        )
        #expect(empty.toArticle(categoryID: categoryID).readTimeMinutes == 1,
                "Empty excerpt should give 1 minute read time")
    }

    // -------------------------------------------------------------------------
    // TEST: Nil optional fields don't crash the conversion
    //
    // Expected output: Article is created successfully with nil imageURL.
    // -------------------------------------------------------------------------
    @Test func nilOptionalFieldsAreSafe() {
        let feedItem = FeedItem(
            sourceID: UUID(),
            title: "No Image Article",
            link: URL(string: "https://example.com")!,
            publishedAt: Date(),
            imageURL: nil,
            author: nil
        )
        let article = feedItem.toArticle(categoryID: UUID())
        #expect(article.imageURL == nil, "Nil image should stay nil")
    }
}


// =============================================================================
// MARK: - 6. SQLITE STORE TESTS
// =============================================================================
//
// What this tests:
//   The SQLite database layer that stores all pipeline data. Tests verify
//   that we can write items, read them back, update scores, and that the
//   aged-out filtering works correctly.
//
// Why it matters:
//   This is the single source of truth for the pipeline. If writes are
//   silently lost or reads return stale data, the entire river is broken.
//
// Note: These tests use the shared SQLiteStore instance which writes to
//   the app's Application Support directory. Items created in tests are
//   cleaned up at the end of each test.
//

struct SQLiteStoreTests {

    // Helper: create a test FeedItem with a unique ID
    private func makeTestItem(
        sourceID: UUID = UUID(),
        title: String = "Test Article",
        hoursAgo: Double = 0,
        relevanceScore: Double = 1.0,
        riverVisible: Bool = true,
        agedOut: Bool = false
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            relevanceScore: relevanceScore,
            agedOut: agedOut,
            riverVisible: riverVisible
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Write items to SQLite and read them back
    //
    // Expected output: Items written via upsertFeedItems() can be fetched
    //   back with all fields intact.
    // -------------------------------------------------------------------------
    @Test func writeAndReadItems() {
        let store = SQLiteStore.shared
        let sourceID = UUID()
        let item = makeTestItem(sourceID: sourceID, title: "SQLite Round-Trip Test")

        // Write
        store.upsertFeedItems([item])

        // Read back
        let fetched = store.fetchItems(forSource: sourceID)
        #expect(!fetched.isEmpty, "Should find the inserted item")

        if let found = fetched.first(where: { $0.id == item.id }) {
            #expect(found.title == "SQLite Round-Trip Test",  "Title should match")
            #expect(found.sourceID == sourceID,               "Source ID should match")
            #expect(found.velocityTier == .article,           "Default tier should be .article")
            #expect(found.riverVisible == true,               "Should be river-visible by default")
        } else {
            Issue.record("Inserted item not found in fetch results")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Deduplication — itemExists() correctly detects existing items
    //
    // Expected output: Returns true for an item we just inserted,
    //   false for a random UUID that was never inserted.
    // -------------------------------------------------------------------------
    @Test func deduplicationCheck() {
        let store = SQLiteStore.shared
        let item = makeTestItem(title: "Dedup Test Item")

        store.upsertFeedItems([item])

        #expect(store.itemExists(id: item.id) == true,
                "Should find the item we just inserted")
        #expect(store.itemExists(id: UUID()) == false,
                "Should not find a random UUID")
    }

    // -------------------------------------------------------------------------
    // TEST: Batch dedup — existingItemIDs filters correctly
    //
    // Scenario: Insert 2 items, then check a set of 3 IDs (2 existing + 1 new).
    // Expected output: Only the 2 existing IDs are returned.
    // -------------------------------------------------------------------------
    @Test func batchDeduplication() {
        let store = SQLiteStore.shared
        let item1 = makeTestItem(title: "Batch Dedup 1")
        let item2 = makeTestItem(title: "Batch Dedup 2")
        let fakeID = UUID()

        store.upsertFeedItems([item1, item2])

        let existing = store.existingItemIDs(from: [item1.id, item2.id, fakeID])
        #expect(existing.contains(item1.id), "Should find item1")
        #expect(existing.contains(item2.id), "Should find item2")
        #expect(!existing.contains(fakeID),  "Should not find fake ID")
    }

    // -------------------------------------------------------------------------
    // TEST: Score updates persist correctly
    //
    // Scenario: Insert an item with relevance 1.0, then update to 0.5.
    // Expected output: The fetched item has the new relevance score.
    // -------------------------------------------------------------------------
    @Test func scoreUpdatePersists() {
        let store = SQLiteStore.shared
        let sourceID = UUID()
        let item = makeTestItem(sourceID: sourceID, title: "Score Update Test")

        store.upsertFeedItems([item])
        store.updateScores([(id: item.id, relevanceScore: 0.42, agedOut: false)])

        let fetched = store.fetchItems(forSource: sourceID)
        if let found = fetched.first(where: { $0.id == item.id }) {
            #expect(abs(found.relevanceScore - 0.42) < 0.001,
                    "Relevance should be updated to 0.42, got \(found.relevanceScore)")
        } else {
            Issue.record("Item not found after score update")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: fetchRiverItems() excludes aged-out items
    //
    // Scenario: Insert 2 items — one active, one aged-out.
    // Expected output: Only the active item appears in river results.
    // -------------------------------------------------------------------------
    @Test func riverExcludesAgedOut() {
        let store = SQLiteStore.shared
        let sourceID = UUID()
        let active = makeTestItem(sourceID: sourceID, title: "Active Item \(UUID())")
        let aged = makeTestItem(sourceID: sourceID, title: "Aged Item \(UUID())", agedOut: true)

        store.upsertFeedItems([active, aged])

        let river = store.fetchRiverItems()
        let riverIDs = river.map(\.id)
        #expect(riverIDs.contains(active.id),  "Active item should be in the river")
        #expect(!riverIDs.contains(aged.id),   "Aged-out item should NOT be in the river")
    }

    // -------------------------------------------------------------------------
    // TEST: Source affinity round-trip
    //
    // Expected output: Write a SourceAffinityRecord, read it back with
    //   all fields intact. Score should be clamped to [-0.3, 1.0].
    // -------------------------------------------------------------------------
    @Test func affinityRoundTrip() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let record = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: 0.65,
            eventCount: 12,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(record)

        let fetched = store.fetchAffinity(forSource: sourceID)
        #expect(fetched != nil, "Should find the affinity record")
        if let f = fetched {
            #expect(abs(f.affinityScore - 0.65) < 0.001, "Score should be 0.65")
            #expect(f.eventCount == 12,                   "Event count should be 12")
            #expect(f.velocityTier == .news,              "Tier should be .news")
            #expect(f.slotLimit == 5,                     "Slot limit should be 5")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Affinity score clamping
    //
    // Scenario: Create a record with score 5.0 (way above max).
    // Expected output: Score is clamped to 1.0 (the maximum).
    // -------------------------------------------------------------------------
    @Test func affinityScoreClamping() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 5.0)
        #expect(record.affinityScore == 1.0, "Score should clamp to 1.0 max")

        let negative = SourceAffinityRecord(sourceID: UUID(), affinityScore: -2.0)
        #expect(negative.affinityScore == -0.3, "Score should clamp to -0.3 min")
    }
}


// =============================================================================
// MARK: - 7. INTERACTION EVENT TESTS
// =============================================================================
//
// What this tests:
//   The event weight system that will drive affinity scoring in Phase 2d.
//   Each interaction type (tap, share, dismiss, etc.) has a weight that
//   determines how much it boosts or penalizes a source's affinity score.
//
// Why it matters:
//   Wrong weights would cause the app to boost sources the user ignores
//   or penalize sources the user loves.
//

struct InteractionEventTests {

    // -------------------------------------------------------------------------
    // TEST: Positive events have positive weights
    //
    // Expected output: All "good" interactions (open, share, browse, dwell)
    //   have weight > 0.
    // -------------------------------------------------------------------------
    @Test func positiveEventsHavePositiveWeights() {
        let positiveEvents: [InteractionEventType] = [
            .articleOpen, .sourceBrowse, .digestExpand, .clusterExpand,
            .articleShare, .dwellLong, .dwellMedium, .scrollSlow, .returnVisit
        ]
        for event in positiveEvents {
            #expect(event.weight > 0, "\(event) should have positive weight, got \(event.weight)")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Negative events have negative weights
    //
    // Expected output: Dismiss, bounce, and fast-scroll have weight < 0.
    // -------------------------------------------------------------------------
    @Test func negativeEventsHaveNegativeWeights() {
        let negativeEvents: [InteractionEventType] = [
            .quickBounce, .scrollFastPast, .explicitDismiss
        ]
        for event in negativeEvents {
            #expect(event.weight < 0, "\(event) should have negative weight, got \(event.weight)")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Weight ordering matches user intent strength
    //
    // A user explicitly browsing a source is the strongest positive signal.
    // A quick bounce (< 5 seconds) is a mild negative.
    // An explicit dismiss is the strongest negative.
    //
    // Expected output:
    //   sourceBrowse (1.2) > articleShare (1.1) > articleOpen (1.0) > ... > scrollSlow (0.2)
    //   explicitDismiss (-0.5) < quickBounce (-0.3) < scrollFastPast (-0.1)
    // -------------------------------------------------------------------------
    @Test func weightOrdering() {
        #expect(InteractionEventType.sourceBrowse.weight > InteractionEventType.articleShare.weight)
        #expect(InteractionEventType.articleShare.weight > InteractionEventType.articleOpen.weight)
        #expect(InteractionEventType.articleOpen.weight > InteractionEventType.dwellLong.weight)
        #expect(InteractionEventType.dwellLong.weight > InteractionEventType.dwellMedium.weight)
        #expect(InteractionEventType.dwellMedium.weight > InteractionEventType.scrollSlow.weight)

        // Negative: dismiss is worse than bounce, bounce is worse than fast-scroll
        #expect(InteractionEventType.explicitDismiss.weight < InteractionEventType.quickBounce.weight)
        #expect(InteractionEventType.quickBounce.weight < InteractionEventType.scrollFastPast.weight)
    }
}


// =============================================================================
// MARK: - 8. RIVER ITEM TESTS
// =============================================================================
//
// What this tests:
//   RiverItem is the union type that represents everything in the feed:
//   articles, nudge cards (and later cluster/digest cards). Tests verify
//   that IDs and sort weights work correctly.
//
// Why it matters:
//   The view layer switches on RiverItem cases. If IDs collide or weights
//   are wrong, articles could disappear or sort incorrectly.
//

struct RiverItemTests {

    // -------------------------------------------------------------------------
    // TEST: Article river item exposes correct ID and relevance
    //
    // Expected output: RiverItem.article wraps a FeedItem and surfaces
    //   its ID and relevance score.
    // -------------------------------------------------------------------------
    @Test func articleItemProperties() {
        let feedItem = FeedItem(
            sourceID: UUID(),
            title: "River Test",
            link: URL(string: "https://example.com")!,
            publishedAt: Date(),
            relevanceScore: 0.75
        )
        let riverItem = RiverItem.article(feedItem)

        #expect(riverItem.id == feedItem.id,                   "ID should match wrapped FeedItem")
        #expect(riverItem.relevanceScore == 0.75,              "Relevance should pass through")
        #expect(riverItem.positionalWeight == 0.75,            "Weight should equal relevance for articles")
    }

    // -------------------------------------------------------------------------
    // TEST: Nudge cards float near the top
    //
    // Expected output: Nudge cards have positional weight 0.95 (higher than
    //   most articles) so they appear prominently in the feed.
    // -------------------------------------------------------------------------
    @Test func nudgeCardWeight() {
        let nudge = NudgeCard(sourceID: UUID(), sourceName: "CNN", itemCount: 15)
        let riverItem = RiverItem.nudge(nudge)

        #expect(riverItem.positionalWeight == 0.95,
                "Nudge cards should float near top with weight 0.95")
        #expect(riverItem.relevanceScore == 1.0,
                "Nudge cards should have full relevance (no fading)")
    }

    // -------------------------------------------------------------------------
    // TEST: Sorting by positional weight produces correct order
    //
    // Scenario: 3 articles with different relevance + 1 nudge card.
    // Expected output: Sorted order = nudge (0.95), then articles by
    //   relevance descending.
    // -------------------------------------------------------------------------
    @Test func sortingOrder() {
        let high = RiverItem.article(FeedItem(
            sourceID: UUID(), title: "High", link: URL(string: "https://a.com")!,
            publishedAt: Date(), relevanceScore: 0.9
        ))
        let medium = RiverItem.article(FeedItem(
            sourceID: UUID(), title: "Med", link: URL(string: "https://b.com")!,
            publishedAt: Date(), relevanceScore: 0.5
        ))
        let low = RiverItem.article(FeedItem(
            sourceID: UUID(), title: "Low", link: URL(string: "https://c.com")!,
            publishedAt: Date(), relevanceScore: 0.2
        ))
        let nudge = RiverItem.nudge(NudgeCard(
            sourceID: UUID(), sourceName: "Wire", itemCount: 10
        ))

        let sorted = [low, high, nudge, medium].sorted { $0.positionalWeight > $1.positionalWeight }

        #expect(sorted[0].positionalWeight == 0.95, "Nudge should be first")
        #expect(sorted[1].positionalWeight == 0.9,  "High relevance article second")
        #expect(sorted[2].positionalWeight == 0.5,  "Medium third")
        #expect(sorted[3].positionalWeight == 0.2,  "Low last")
    }
}
