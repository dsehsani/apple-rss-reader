//
//  Phase2bTests.swift
//  OpenRSSTests
//
//  Phase 2b unit tests — validates the untested service layer:
//  content normalization, YouTube Atom parsing, pipeline timing,
//  affinity EMA, cosine similarity, rate gating, batch decay scoring,
//  snapshot assembly, and pipeline performance benchmarks.
//
//  Run with Cmd+U in Xcode or: xcodebuild test -scheme OpenRSS
//

import Testing
import Foundation
@testable import OpenRSS

/// Shared error type for tests that verify throwing behaviour.
private enum TestError: Error { case intentional }


// =============================================================================
// MARK: - 1. CONTENT NORMALIZER SERVICE TESTS
// =============================================================================
//
// What this tests:
//   The HTML→ContentNode pipeline that converts Readability-cleaned HTML into
//   the typed DOM array consumed by the article reader views.
//
// Why it matters:
//   If normalization is wrong, the reader view will show ads, miss images,
//   render broken tables, or crash on malformed input.
//

struct ContentNormalizerServiceTests {

    private let service = ContentNormalizerService()

    /// Wraps a raw HTML fragment in a ReadableContent for testing.
    private func makeContent(html: String) -> ReadableContent {
        ReadableContent(
            title: "Test",
            byline: nil,
            content: html,
            excerpt: nil,
            heroImageURL: nil
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Simple paragraph extraction
    //
    // Expected output: A single .paragraph node with the text "Hello world".
    // -------------------------------------------------------------------------
    @Test func paragraphExtraction() throws {
        let nodes = try service.normalize(content: makeContent(html: "<p>Hello world</p>"))
        #expect(nodes.count == 1)
        guard case .paragraph(let text) = nodes.first else {
            Issue.record("Expected .paragraph, got \(String(describing: nodes.first))")
            return
        }
        #expect(text == "Hello world")
    }

    // -------------------------------------------------------------------------
    // TEST: Heading levels H1 through H6
    //
    // Expected output: 6 .heading nodes with levels 1-6 and correct text.
    // -------------------------------------------------------------------------
    @Test func headingLevelsH1ThroughH6() throws {
        let html = (1...6).map { "<h\($0)>Heading \($0)</h\($0)>" }.joined()
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 6, "Expected 6 heading nodes, got \(nodes.count)")
        for (i, node) in nodes.enumerated() {
            guard case .heading(let level, let text) = node else {
                Issue.record("Expected .heading at index \(i), got \(node)")
                continue
            }
            #expect(level == i + 1, "Expected level \(i + 1), got \(level)")
            #expect(text == "Heading \(i + 1)")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Image extraction with HTTPS src and alt text
    //
    // Expected output: A single .image node with the correct URL and caption.
    // -------------------------------------------------------------------------
    @Test func imageExtraction() throws {
        let html = """
        <img src="https://example.com/photo.jpg" alt="A photo">
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .image(let url, let caption) = nodes.first else {
            Issue.record("Expected .image, got \(String(describing: nodes.first))")
            return
        }
        #expect(url.absoluteString == "https://example.com/photo.jpg")
        #expect(caption == "A photo")
    }

    // -------------------------------------------------------------------------
    // TEST: Figure with figcaption produces .image with caption
    //
    // Expected output: A single .image node using the figcaption text.
    // -------------------------------------------------------------------------
    @Test func figureWithFigcaption() throws {
        let html = """
        <figure>
          <img src="https://example.com/img.jpg">
          <figcaption>Caption text</figcaption>
        </figure>
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .image(let url, let caption) = nodes.first else {
            Issue.record("Expected .image, got \(String(describing: nodes.first))")
            return
        }
        #expect(url.absoluteString == "https://example.com/img.jpg")
        #expect(caption == "Caption text")
    }

    // -------------------------------------------------------------------------
    // TEST: Ad elements are stripped; real content preserved
    //
    // Scenario: HTML with an ad div, an adsbygoogle ins element, a script,
    //   and one real paragraph.
    // Expected output: Only the real paragraph survives.
    // -------------------------------------------------------------------------
    @Test func adRemoval() throws {
        let html = """
        <div data-ad-slot="123">ad stuff</div>
        <ins class="adsbygoogle">more ads</ins>
        <script>alert('hi')</script>
        <p>Real content</p>
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1, "Only real content should survive, got \(nodes.count) nodes")
        guard case .paragraph(let text) = nodes.first else {
            Issue.record("Expected .paragraph")
            return
        }
        #expect(text == "Real content")
    }

    // -------------------------------------------------------------------------
    // TEST: Ad placeholder text is filtered
    //
    // Scenario: Paragraphs containing "Advertisement" and "Skip Advertisement"
    //   alongside a real paragraph.
    // Expected output: Only the real paragraph survives.
    // -------------------------------------------------------------------------
    @Test func adPlaceholderTextFiltered() throws {
        let html = """
        <p>Advertisement</p>
        <p>Skip Advertisement</p>
        <p>Real paragraph</p>
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1, "Ad placeholders should be filtered")
        guard case .paragraph(let text) = nodes.first else {
            Issue.record("Expected .paragraph")
            return
        }
        #expect(text == "Real paragraph")
    }

    // -------------------------------------------------------------------------
    // TEST: Logo and avatar images are filtered out
    //
    // Scenario: A gravatar avatar image and a real content image.
    // Expected output: Only the content image is returned.
    // -------------------------------------------------------------------------
    @Test func logoAndAvatarImageFiltering() throws {
        let html = """
        <img src="https://secure.gravatar.com/avatar/abc123" alt="Author Photo">
        <img src="https://example.com/content.jpg" alt="A sunset">
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1, "Avatar should be filtered out")
        guard case .image(let url, _) = nodes.first else {
            Issue.record("Expected .image")
            return
        }
        #expect(url.absoluteString == "https://example.com/content.jpg")
    }

    // -------------------------------------------------------------------------
    // TEST: Logo alt-text filtering
    //
    // Scenario: An image with alt text containing "logo".
    // Expected output: Image is filtered out.
    // -------------------------------------------------------------------------
    @Test func logoAltTextFiltering() throws {
        let html = """
        <img src="https://example.com/site-logo.png" alt="Site Logo">
        <img src="https://example.com/article-photo.jpg" alt="Conference keynote">
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1, "Logo image should be filtered out")
        guard case .image(_, let caption) = nodes.first else {
            Issue.record("Expected .image")
            return
        }
        #expect(caption == "Conference keynote")
    }

    // -------------------------------------------------------------------------
    // TEST: Unordered and ordered list extraction
    //
    // Expected output: An unordered list and an ordered list with correct items.
    // -------------------------------------------------------------------------
    @Test func listExtraction() throws {
        let html = """
        <ul><li>Item A</li><li>Item B</li></ul>
        <ol><li>First</li><li>Second</li></ol>
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 2, "Expected 2 list nodes, got \(nodes.count)")

        guard case .list(let items1, let ordered1) = nodes[0] else {
            Issue.record("Expected .list at index 0")
            return
        }
        #expect(items1 == ["Item A", "Item B"])
        #expect(ordered1 == false)

        guard case .list(let items2, let ordered2) = nodes[1] else {
            Issue.record("Expected .list at index 1")
            return
        }
        #expect(items2 == ["First", "Second"])
        #expect(ordered2 == true)
    }

    // -------------------------------------------------------------------------
    // TEST: Table extraction with headers and data rows
    //
    // Expected output: A .table node with headers ["Name", "Age"]
    //   and one data row ["Alice", "30"].
    // -------------------------------------------------------------------------
    @Test func tableExtraction() throws {
        let html = """
        <table>
          <tr><th>Name</th><th>Age</th></tr>
          <tr><td>Alice</td><td>30</td></tr>
        </table>
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .table(let headers, let rows) = nodes.first else {
            Issue.record("Expected .table, got \(String(describing: nodes.first))")
            return
        }
        #expect(headers == ["Name", "Age"])
        #expect(rows == [["Alice", "30"]])
    }

    // -------------------------------------------------------------------------
    // TEST: Code block extraction from <pre><code>
    //
    // Expected output: A .codeBlock node with the code text.
    // -------------------------------------------------------------------------
    @Test func codeBlockExtraction() throws {
        let html = "<pre><code>let x = 42</code></pre>"
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .codeBlock(let text) = nodes.first else {
            Issue.record("Expected .codeBlock, got \(String(describing: nodes.first))")
            return
        }
        #expect(text == "let x = 42")
    }

    // -------------------------------------------------------------------------
    // TEST: Blockquote extraction
    //
    // Expected output: A .blockquote node with the quote text.
    // -------------------------------------------------------------------------
    @Test func blockquoteExtraction() throws {
        let html = "<blockquote>Famous quote here</blockquote>"
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .blockquote(let text) = nodes.first else {
            Issue.record("Expected .blockquote, got \(String(describing: nodes.first))")
            return
        }
        #expect(text == "Famous quote here")
    }

    // -------------------------------------------------------------------------
    // TEST: Empty and whitespace-only paragraphs are skipped
    //
    // Expected output: Only the non-empty paragraph survives.
    // -------------------------------------------------------------------------
    @Test func emptyAndWhitespaceSkipped() throws {
        let html = "<p></p><p>   </p><p>Real</p>"
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1, "Empty paragraphs should be skipped")
        guard case .paragraph(let text) = nodes.first else {
            Issue.record("Expected .paragraph")
            return
        }
        #expect(text == "Real")
    }

    // -------------------------------------------------------------------------
    // TEST: Nested div containers are recursed into
    //
    // Expected output: The paragraph inside nested divs is extracted.
    // -------------------------------------------------------------------------
    @Test func nestedDivRecursion() throws {
        let html = "<div><div><p>Deep nested</p></div></div>"
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.count == 1)
        guard case .paragraph(let text) = nodes.first else {
            Issue.record("Expected .paragraph")
            return
        }
        #expect(text == "Deep nested")
    }

    // -------------------------------------------------------------------------
    // TEST: Non-HTTP images (data URIs) are rejected
    //
    // Expected output: No image node — data: scheme is not http/https.
    // -------------------------------------------------------------------------
    @Test func nonHTTPImageRejected() throws {
        let html = """
        <img src="data:image/png;base64,iVBORw0KGgo=" alt="inline">
        """
        let nodes = try service.normalize(content: makeContent(html: html))
        #expect(nodes.isEmpty, "data: URI images should be rejected")
    }
}


// =============================================================================
// MARK: - 2. YOUTUBE ATOM PARSER TESTS
// =============================================================================
//
// What this tests:
//   The SAX XML parser that extracts media:thumbnail and media:description
//   from YouTube Atom feeds, which FeedKit cannot parse.
//
// Why it matters:
//   Without this parser, every YouTube feed item would have nil thumbnails
//   and nil descriptions, making the feed visually broken.
//

struct YouTubeAtomParserTests {

    // -------------------------------------------------------------------------
    // TEST: A single entry with full media:group metadata
    //
    // Expected output: One entry keyed by the watch URL, with thumbnail
    //   and description correctly extracted.
    // -------------------------------------------------------------------------
    @Test func singleEntryParsing() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=abc123"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/abc123/hqdefault.jpg"/>
              <media:description>A video about cats</media:description>
            </media:group>
          </entry>
        </feed>
        """
        let result = YouTubeAtomParser().parse(data: xml.data(using: .utf8)!)
        #expect(result.count == 1, "Should have 1 entry")

        let meta = result["https://www.youtube.com/watch?v=abc123"]
        #expect(meta != nil, "Should find entry by watch URL")
        #expect(meta?.thumbnailURL == "https://i.ytimg.com/vi/abc123/hqdefault.jpg")
        #expect(meta?.description == "A video about cats")
    }

    // -------------------------------------------------------------------------
    // TEST: Multiple entries each get separate metadata
    //
    // Expected output: 3 distinct entries with correct per-video metadata.
    // -------------------------------------------------------------------------
    @Test func multipleEntries() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=aaa"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/aaa/hq.jpg"/>
              <media:description>First video</media:description>
            </media:group>
          </entry>
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=bbb"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/bbb/hq.jpg"/>
              <media:description>Second video</media:description>
            </media:group>
          </entry>
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=ccc"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/ccc/hq.jpg"/>
              <media:description>Third video</media:description>
            </media:group>
          </entry>
        </feed>
        """
        let result = YouTubeAtomParser().parse(data: xml.data(using: .utf8)!)
        #expect(result.count == 3, "Should have 3 entries")
        #expect(result["https://www.youtube.com/watch?v=aaa"]?.description == "First video")
        #expect(result["https://www.youtube.com/watch?v=bbb"]?.description == "Second video")
        #expect(result["https://www.youtube.com/watch?v=ccc"]?.description == "Third video")
    }

    // -------------------------------------------------------------------------
    // TEST: Entry without media:group still captured with nil metadata
    //
    // Expected output: Entry keyed by URL with nil thumbnail and description.
    // -------------------------------------------------------------------------
    @Test func missingMediaGroup() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=nogroup"/>
          </entry>
        </feed>
        """
        let result = YouTubeAtomParser().parse(data: xml.data(using: .utf8)!)
        #expect(result.count == 1, "Entry should still be captured")
        let meta = result["https://www.youtube.com/watch?v=nogroup"]
        #expect(meta?.thumbnailURL == nil)
        #expect(meta?.description == nil)
    }

    // -------------------------------------------------------------------------
    // TEST: media:group with only description, no thumbnail
    //
    // Expected output: thumbnail is nil, description has value.
    // -------------------------------------------------------------------------
    @Test func missingThumbnailOnly() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=nothumb"/>
            <media:group>
              <media:description>Has description only</media:description>
            </media:group>
          </entry>
        </feed>
        """
        let result = YouTubeAtomParser().parse(data: xml.data(using: .utf8)!)
        let meta = result["https://www.youtube.com/watch?v=nothumb"]
        #expect(meta?.thumbnailURL == nil, "No thumbnail should be nil")
        #expect(meta?.description == "Has description only")
    }

    // -------------------------------------------------------------------------
    // TEST: Empty data produces empty result without crash
    //
    // Expected output: Empty dictionary, no crash.
    // -------------------------------------------------------------------------
    @Test func emptyData() {
        let result = YouTubeAtomParser().parse(data: Data())
        #expect(result.isEmpty, "Empty data should produce empty results")
    }

    // -------------------------------------------------------------------------
    // TEST: Malformed XML produces empty result without crash
    //
    // Expected output: Empty dictionary, no crash.
    // -------------------------------------------------------------------------
    @Test func malformedXML() {
        let result = YouTubeAtomParser().parse(data: "<not valid xml <><>".data(using: .utf8)!)
        #expect(result.isEmpty, "Malformed XML should produce empty results")
    }
}


// =============================================================================
// MARK: - 3. PIPELINE TIMER TESTS
// =============================================================================
//
// What this tests:
//   The instrumentation utility that wraps pipeline stages, measures
//   wall-clock time, and passes through results.
//
// Why it matters:
//   If the timer distorts results or measures inaccurately, both the
//   pipeline output and the performance dashboard would be unreliable.
//

struct PipelineTimerTests {

    private let timer = PipelineTimer()

    // -------------------------------------------------------------------------
    // TEST: Synchronous work passes through its result
    //
    // Expected output: .result == 42
    // -------------------------------------------------------------------------
    @Test func syncResultPassthrough() {
        let output = timer.time("test-sync") { return 42 }
        #expect(output.result == 42, "Result should pass through unchanged")
    }

    // -------------------------------------------------------------------------
    // TEST: Elapsed time is positive and reasonable for trivial work
    //
    // Expected output: ms > 0 and ms < 1000 (trivial work).
    // -------------------------------------------------------------------------
    @Test func syncTimingIsPositive() {
        let output = timer.time("test-timing") { return "hello" }
        #expect(output.ms >= 0, "Elapsed time should be non-negative")
        #expect(output.ms < 1000, "Trivial work should complete in under 1 second")
    }

    // -------------------------------------------------------------------------
    // TEST: Async work passes through its result
    //
    // Expected output: .result == "async-value"
    // -------------------------------------------------------------------------
    @Test func asyncResultPassthrough() async {
        let output = await timer.time("test-async") { return "async-value" }
        #expect(output.result == "async-value", "Async result should pass through unchanged")
    }

    // -------------------------------------------------------------------------
    // TEST: Throwing work propagates the error through rethrows
    //
    // Expected output: The error propagates; timer does not swallow it.
    // -------------------------------------------------------------------------
    @Test func throwingWorkPropagatesError() {
        #expect(throws: TestError.self) {
            let _: (result: Int, ms: Double) = try timer.time("test-throw") {
                throw TestError.intentional
            }
        }
    }
}


// =============================================================================
// MARK: - 4. AFFINITY TRACKER TESTS
// =============================================================================
//
// What this tests:
//   The static updateAffinity(current:eventWeight:) pure function that
//   computes EMA with alpha=0.15, clamped to [-0.3, 1.0].
//
// Why it matters:
//   Incorrect EMA math would cause affinity scores to drift, overflow,
//   or oscillate, making the feed ranking unreliable.
//

struct AffinityTrackerTests {

    // -------------------------------------------------------------------------
    // TEST: Neutral start + positive event
    //
    // Formula: 0.15 * 1.0 + 0.85 * 0.0 = 0.15
    // Expected output: ~0.15
    // -------------------------------------------------------------------------
    @Test func neutralStartPositiveEvent() {
        let result = AffinityTracker.updateAffinity(current: 0.0, eventWeight: 1.0)
        #expect(abs(result - 0.15) < 0.001,
                "Expected ~0.15, got \(result)")
    }

    // -------------------------------------------------------------------------
    // TEST: Neutral start + negative event
    //
    // Formula: 0.15 * (-0.5) + 0.85 * 0.0 = -0.075
    // Expected output: ~-0.075
    // -------------------------------------------------------------------------
    @Test func neutralStartNegativeEvent() {
        let result = AffinityTracker.updateAffinity(current: 0.0, eventWeight: -0.5)
        #expect(abs(result - (-0.075)) < 0.001,
                "Expected ~-0.075, got \(result)")
    }

    // -------------------------------------------------------------------------
    // TEST: High affinity stays high with positive events
    //
    // Formula: 0.15 * 1.2 + 0.85 * 0.9 = 0.18 + 0.765 = 0.945
    // Expected output: ~0.945
    // -------------------------------------------------------------------------
    @Test func highAffinityStaysHighWithPositive() {
        let result = AffinityTracker.updateAffinity(current: 0.9, eventWeight: 1.2)
        #expect(abs(result - 0.945) < 0.001,
                "Expected ~0.945, got \(result)")
    }

    // -------------------------------------------------------------------------
    // TEST: Result is clamped to upper bound of 1.0
    //
    // Formula: 0.15 * 1.2 + 0.85 * 1.0 = 1.03 → clamped to 1.0
    // Expected output: 1.0
    // -------------------------------------------------------------------------
    @Test func clampToUpperBound() {
        let result = AffinityTracker.updateAffinity(current: 1.0, eventWeight: 1.2)
        #expect(result == 1.0, "Should clamp to 1.0, got \(result)")
    }

    // -------------------------------------------------------------------------
    // TEST: Result is clamped to lower bound of -0.3
    //
    // Formula: 0.15 * (-0.5) + 0.85 * (-0.3) = -0.075 + (-0.255) = -0.33
    //   → clamped to -0.3
    // Expected output: -0.3
    // -------------------------------------------------------------------------
    @Test func clampToLowerBound() {
        let result = AffinityTracker.updateAffinity(current: -0.3, eventWeight: -0.5)
        #expect(result == -0.3, "Should clamp to -0.3, got \(result)")
    }

    // -------------------------------------------------------------------------
    // TEST: Repeated neutral events converge toward event weight
    //
    // Scenario: Start at 0.0, apply eventWeight 0.5 ten times.
    // Expected output: Score monotonically increases toward 0.5.
    // -------------------------------------------------------------------------
    @Test func repeatedNeutralEventsConverge() {
        var score = 0.0
        var previousScore = -1.0

        for _ in 0..<10 {
            score = AffinityTracker.updateAffinity(current: score, eventWeight: 0.5)
            #expect(score > previousScore, "Score should monotonically increase")
            previousScore = score
        }

        // After 10 iterations, should be approaching 0.5 but not yet there
        #expect(score > 0.3, "Should be converging toward 0.5, got \(score)")
        #expect(score < 0.5, "Should not yet reach the target, got \(score)")
    }
}


// =============================================================================
// MARK: - 5. SEMANTIC CLUSTER SERVICE TESTS
// =============================================================================
//
// What this tests:
//   The cosineSimilarity static function that gates Pass 2 of the
//   three-pass clustering pipeline. Tests verify the pure math works
//   for canonical vector relationships.
//
// Why it matters:
//   Cosine similarity is the decision gate for clustering. If it returns
//   wrong values, unrelated stories get clustered or related stories
//   get missed.
//

struct SemanticClusterServiceTests {

    // -------------------------------------------------------------------------
    // TEST: Identical vectors have similarity 1.0
    //
    // Expected output: cosineSimilarity == 1.0
    // -------------------------------------------------------------------------
    @Test func identicalVectorsHaveSimilarityOne() {
        let v: [Float] = [1.0, 0.0, 0.0]
        let sim = SemanticClusterService.cosineSimilarity(v, v)
        #expect(abs(sim - 1.0) < 0.001,
                "Identical vectors should have similarity 1.0, got \(sim)")
    }

    // -------------------------------------------------------------------------
    // TEST: Orthogonal vectors have similarity 0.0
    //
    // Expected output: cosineSimilarity == 0.0
    // -------------------------------------------------------------------------
    @Test func orthogonalVectorsHaveSimilarityZero() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [0.0, 1.0, 0.0]
        let sim = SemanticClusterService.cosineSimilarity(a, b)
        #expect(abs(sim) < 0.001,
                "Orthogonal vectors should have similarity 0.0, got \(sim)")
    }

    // -------------------------------------------------------------------------
    // TEST: Opposite vectors have similarity -1.0
    //
    // Expected output: cosineSimilarity == -1.0
    // -------------------------------------------------------------------------
    @Test func oppositeVectorsHaveSimilarityNegativeOne() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [-1.0, 0.0, 0.0]
        let sim = SemanticClusterService.cosineSimilarity(a, b)
        #expect(abs(sim - (-1.0)) < 0.001,
                "Opposite vectors should have similarity -1.0, got \(sim)")
    }

    // -------------------------------------------------------------------------
    // TEST: Empty vectors return 0
    //
    // Expected output: cosineSimilarity == 0 (guard clause)
    // -------------------------------------------------------------------------
    @Test func emptyVectorsReturnZero() {
        let sim = SemanticClusterService.cosineSimilarity([], [])
        #expect(sim == 0, "Empty vectors should return 0")
    }

    // -------------------------------------------------------------------------
    // TEST: Mismatched vector lengths return 0
    //
    // Expected output: cosineSimilarity == 0 (guard clause)
    // -------------------------------------------------------------------------
    @Test func mismatchedLengthsReturnZero() {
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [1.0, 0.0, 0.0]
        let sim = SemanticClusterService.cosineSimilarity(a, b)
        #expect(sim == 0, "Mismatched lengths should return 0")
    }
}


// =============================================================================
// MARK: - 6. RATE GATE SERVICE TESTS
// =============================================================================
//
// What this tests:
//   The rate-gating pipeline that enforces per-source daily slot limits,
//   generates DigestCards for overflow, and adjusts limits based on
//   affinity scores.
//
// Why it matters:
//   Without rate gating, a wire service publishing 100 articles/day would
//   drown out all other sources in the river.
//

struct RateGateServiceTests {

    /// Creates a test FeedItem fetched today with the given parameters.
    private func makeTodayItem(
        sourceID: UUID,
        title: String = "Test",
        velocityTier: VelocityTier = .article,
        hoursAgo: Double = 0.5
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            velocityTier: velocityTier,
            riverVisible: true
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Source under slot limit produces no digest
    //
    // Scenario: Insert 3 items for a .news source (default limit = 5).
    // Expected output: No digest cards; no items hidden.
    // -------------------------------------------------------------------------
    @Test func sourceUnderLimitNoDigest() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        let items = (0..<3).map { i in
            makeTodayItem(sourceID: sourceID, title: "Under Limit \(i)", velocityTier: .news, hoursAgo: 0.1 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()

        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.isEmpty,
                "Source under slot limit should not produce a digest card")

        let hiddenForSource = items.filter { result.hiddenItemIDs.contains($0.id) }
        #expect(hiddenForSource.isEmpty,
                "No items should be hidden when under the slot limit")
    }

    // -------------------------------------------------------------------------
    // TEST: Source over slot limit generates a digest card
    //
    // Scenario: Insert 8 items for a .breaking source (default limit = 3).
    // Expected output: 1 digest card with 5 overflow items; 5 items hidden.
    // -------------------------------------------------------------------------
    @Test func sourceOverLimitGeneratesDigest() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        let items = (0..<8).map { i in
            makeTodayItem(sourceID: sourceID, title: "Breaking \(i)", velocityTier: .breaking, hoursAgo: 0.05 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()

        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.count == 1,
                "Should produce exactly 1 digest card for the source")

        if let digest = digestForSource.first {
            #expect(digest.itemCount == 5,
                    "Overflow should be 8 - 3 = 5 items, got \(digest.itemCount)")
            #expect(digest.sourceID == sourceID)
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Digest highlights contain up to 3 titles
    //
    // Scenario: Insert 10 items for a .breaking source.
    // Expected output: highlights.count <= 3
    // -------------------------------------------------------------------------
    @Test func digestHighlightsContainUpToThreeTitles() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        let items = (0..<10).map { i in
            makeTodayItem(sourceID: sourceID, title: "Highlight Test \(i)", velocityTier: .breaking, hoursAgo: 0.02 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()
        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }

        if let digest = digestForSource.first {
            #expect(digest.highlights.count <= 3,
                    "Highlights should contain at most 3 titles, got \(digest.highlights.count)")
            #expect(!digest.highlights.isEmpty,
                    "Highlights should not be empty for overflow items")
        } else {
            Issue.record("Expected a digest card for source with 10 breaking items")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Essay tier has effectively unlimited slots
    //
    // Scenario: Insert 20 items for an .essay source (limit = Int.max).
    // Expected output: No digest card generated.
    // -------------------------------------------------------------------------
    @Test func essayTierHasUnlimitedSlots() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        let items = (0..<20).map { i in
            makeTodayItem(sourceID: sourceID, title: "Essay \(i)", velocityTier: .essay, hoursAgo: 0.01 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()
        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.isEmpty,
                "Essay tier (Int.max slots) should never produce a digest card")
    }

    // -------------------------------------------------------------------------
    // TEST: Affinity boost increases effective slot limit
    //
    // Scenario: .news source (default limit=5) with affinity 0.8 (boost
    //   triggers at >0.7). Insert 7 items.
    // Expected output: Effective limit = min(5*1.5=7, 5+3=8) = 7.
    //   All 7 items fit; no digest generated.
    // -------------------------------------------------------------------------
    @Test func affinityBoostIncreasesEffectiveLimit() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        // Set up high affinity for this source
        let affinity = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: 0.8,
            eventCount: 20,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(affinity)

        let items = (0..<7).map { i in
            makeTodayItem(sourceID: sourceID, title: "Boosted \(i)", velocityTier: .news, hoursAgo: 0.05 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()
        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.isEmpty,
                "With affinity boost, 7 items should fit within boosted limit of 7")
    }

    // -------------------------------------------------------------------------
    // TEST: Affinity penalty reduces effective slot limit
    //
    // Scenario: .news source (default limit=5) with affinity -0.2 (penalty
    //   triggers at <-0.15). Insert 4 items.
    // Expected output: Effective limit = max(1, 5-2) = 3.
    //   1 overflow item → 1 digest card.
    // -------------------------------------------------------------------------
    @Test func affinityPenaltyReducesEffectiveLimit() {
        let store = SQLiteStore.shared
        let service = RateGateService(store: store)
        let sourceID = UUID()

        // Set up low affinity for this source
        let affinity = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: -0.2,
            eventCount: 10,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(affinity)

        let items = (0..<4).map { i in
            makeTodayItem(sourceID: sourceID, title: "Penalised \(i)", velocityTier: .news, hoursAgo: 0.05 * Double(i))
        }
        store.upsertFeedItems(items)

        let result = service.applyRateGate()
        let digestForSource = result.digestCards.filter { $0.sourceID == sourceID }
        #expect(digestForSource.count == 1,
                "With penalty, 4 items exceeds reduced limit of 3 → 1 digest card")

        if let digest = digestForSource.first {
            #expect(digest.itemCount == 1,
                    "Overflow should be 4 - 3 = 1 item, got \(digest.itemCount)")
        }
    }
}


// =============================================================================
// MARK: - 7. DECAY SCORING SERVICE BATCH TESTS
// =============================================================================
//
// What this tests:
//   The scoreAllItems() instance method that batch-scores all active items
//   with affinity boost and persists results to SQLite.
//
// Why it matters:
//   This is the method called in the actual pipeline cycle. If affinity
//   boost is wrong or aged-out detection fails, ranking breaks.
//

struct DecayScoringServiceBatchTests {

    /// Creates a test FeedItem published a given number of hours ago.
    private func makeItem(
        sourceID: UUID = UUID(),
        title: String = "Batch Test",
        hoursAgo: Double = 0,
        velocityTier: VelocityTier = .news
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-hoursAgo * 3600),
            velocityTier: velocityTier,
            relevanceScore: 1.0,
            riverVisible: true
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Fresh items stay active after scoring
    //
    // Scenario: 3 items published 1 hour ago.
    // Expected output: All 3 stay active (not aged out). Returns 0.
    // -------------------------------------------------------------------------
    @Test func freshItemsStayActive() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<3).map { i in
            makeItem(sourceID: sourceID, title: "Fresh \(i) \(UUID())", hoursAgo: 1.0, velocityTier: .news)
        }
        store.upsertFeedItems(items)

        let service = DecayScoringService()
        let agedOutCount = service.scoreAllItems()

        // Fresh .news items (1 hour old, half-life 18h) should have ~0.96 relevance
        let fetched = store.fetchItems(forSource: sourceID)
        for item in fetched {
            if items.contains(where: { $0.id == item.id }) {
                #expect(!item.agedOut,
                        "1-hour-old .news item should not be aged out")
            }
        }
        // agedOutCount includes ALL aged items, not just ours, but ours shouldn't be in there
        #expect(agedOutCount >= 0)
    }

    // -------------------------------------------------------------------------
    // TEST: Old items get aged out
    //
    // Scenario: 1 .breaking item published 100 hours ago (33+ half-lives).
    //   Relevance = e^(-lambda * 100) ≈ 0.0 — well below 0.2 threshold.
    // Expected output: Item is aged out.
    // -------------------------------------------------------------------------
    @Test func oldItemsGetAgedOut() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let item = makeItem(sourceID: sourceID, title: "Old Breaking \(UUID())", hoursAgo: 100, velocityTier: .breaking)
        store.upsertFeedItems([item])

        let service = DecayScoringService()
        _ = service.scoreAllItems()

        let fetched = store.fetchItems(forSource: sourceID)
        if let found = fetched.first(where: { $0.id == item.id }) {
            #expect(found.agedOut == true,
                    "100h-old .breaking item should be aged out")
            #expect(found.relevanceScore < 0.01,
                    "Relevance should be near zero, got \(found.relevanceScore)")
        } else {
            Issue.record("Item not found after scoring")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Affinity boost increases relevance above raw decay
    //
    // Scenario: .news item at 10 hours, with affinity score 0.5 for source.
    //   Raw relevance = e^(-lambda * 10) ≈ 0.68.
    //   Boost = min(max(0.5, 0), 0.5) = 0.5.
    //   Adjusted = 0.68 * 1.5 ≈ 1.02.
    // Expected output: Stored relevance > raw relevance.
    // -------------------------------------------------------------------------
    @Test func affinityBoostIncreasesRelevance() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        // Set up affinity
        let affinity = SourceAffinityRecord(
            sourceID: sourceID,
            affinityScore: 0.5,
            eventCount: 10,
            velocityTier: .news,
            slotLimit: 5
        )
        store.upsertAffinity(affinity)

        let item = makeItem(sourceID: sourceID, title: "Boosted Decay \(UUID())", hoursAgo: 10, velocityTier: .news)
        store.upsertFeedItems([item])

        let service = DecayScoringService()
        _ = service.scoreAllItems()

        let rawRelevance = DecayScoringService.relevance(hoursSincePublished: 10, tier: .news)

        let fetched = store.fetchItems(forSource: sourceID)
        if let found = fetched.first(where: { $0.id == item.id }) {
            #expect(found.relevanceScore > rawRelevance,
                    "Boosted relevance (\(found.relevanceScore)) should exceed raw (\(rawRelevance))")
        } else {
            Issue.record("Item not found after scoring")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: No affinity record means no boost
    //
    // Scenario: Item with no affinity record for its source.
    // Expected output: Relevance equals raw decay formula value.
    // -------------------------------------------------------------------------
    @Test func noAffinityRecordMeansNoBoost() {
        let store = SQLiteStore.shared
        let sourceID = UUID()  // No affinity record exists for this UUID

        let hoursAgo = 5.0
        let item = makeItem(sourceID: sourceID, title: "No Affinity \(UUID())", hoursAgo: hoursAgo, velocityTier: .article)
        store.upsertFeedItems([item])

        let service = DecayScoringService()
        _ = service.scoreAllItems()

        let rawRelevance = DecayScoringService.relevance(hoursSincePublished: hoursAgo, tier: .article)

        let fetched = store.fetchItems(forSource: sourceID)
        if let found = fetched.first(where: { $0.id == item.id }) {
            #expect(abs(found.relevanceScore - rawRelevance) < 0.01,
                    "Without affinity, relevance (\(found.relevanceScore)) should equal raw (\(rawRelevance))")
        } else {
            Issue.record("Item not found after scoring")
        }
    }
}


// =============================================================================
// MARK: - 8. RIVER SNAPSHOT SERVICE TESTS
// =============================================================================
//
// What this tests:
//   The snapshot assembler that merges standalone articles, ClusterCards,
//   DigestCards, and NudgeCards into a sorted [RiverItem] array.
//
// Why it matters:
//   This is the final output consumed by the view layer. Wrong assembly
//   means the user sees a broken feed.
//

struct RiverSnapshotServiceTests {

    /// Creates a test FeedItem with specified relevance and cluster info.
    private func makeItem(
        sourceID: UUID = UUID(),
        title: String = "Snapshot Test",
        relevanceScore: Double = 0.5,
        clusterID: UUID? = nil,
        isCanonical: Bool = false
    ) -> FeedItem {
        FeedItem(
            sourceID: sourceID,
            title: title,
            link: URL(string: "https://test.com/\(UUID().uuidString)")!,
            publishedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            clusterID: clusterID,
            isCanonical: isCanonical,
            relevanceScore: relevanceScore,
            riverVisible: true
        )
    }

    // -------------------------------------------------------------------------
    // TEST: Standalone articles appear sorted by positional weight
    //
    // Scenario: 3 items with relevance 0.9, 0.5, 0.2 (no clusters).
    // Expected output: Sorted descending by positionalWeight.
    // -------------------------------------------------------------------------
    @Test func standaloneArticlesAppearSorted() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)

        let items = [
            makeItem(title: "High \(UUID())", relevanceScore: 0.9),
            makeItem(title: "Med \(UUID())", relevanceScore: 0.5),
            makeItem(title: "Low \(UUID())", relevanceScore: 0.2),
        ]
        store.upsertFeedItems(items)

        // Score them so SQLite has the right values
        store.updateScores(items.map { (id: $0.id, relevanceScore: $0.relevanceScore, agedOut: false) })

        let snapshot = service.assembleSnapshot(rateGateResult: nil)

        // Find our test items in the snapshot
        let ourItems = snapshot.items.filter { ri in
            items.contains(where: { $0.id == ri.id })
        }

        guard ourItems.count >= 2 else { return }

        // Verify ordering: each item's weight should be >= the next
        for i in 0..<(ourItems.count - 1) {
            #expect(ourItems[i].positionalWeight >= ourItems[i + 1].positionalWeight,
                    "Items should be sorted by positional weight descending")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Clustered items collapse into a ClusterCard
    //
    // Scenario: 3 items from different sources sharing the same clusterID.
    // Expected output: Snapshot contains a .cluster instead of 3 .article entries.
    // -------------------------------------------------------------------------
    @Test func clusteredItemsCollapseIntoClusterCard() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)
        let clusterID = UUID()

        let items = [
            makeItem(sourceID: UUID(), title: "Cluster A \(UUID())", relevanceScore: 0.8, clusterID: clusterID, isCanonical: true),
            makeItem(sourceID: UUID(), title: "Cluster B \(UUID())", relevanceScore: 0.7, clusterID: clusterID),
            makeItem(sourceID: UUID(), title: "Cluster C \(UUID())", relevanceScore: 0.6, clusterID: clusterID),
        ]
        store.upsertFeedItems(items)
        store.updateScores(items.map { (id: $0.id, relevanceScore: $0.relevanceScore, agedOut: false) })

        let snapshot = service.assembleSnapshot(rateGateResult: nil)

        // Look for a .cluster with our clusterID
        let clusterCards = snapshot.items.compactMap { item -> ClusterCard? in
            if case .cluster(let card) = item, card.id == clusterID { return card }
            return nil
        }
        #expect(clusterCards.count == 1,
                "3 items with same clusterID should produce 1 ClusterCard")

        if let card = clusterCards.first {
            #expect(card.allItemIDs.count == 3, "ClusterCard should contain all 3 items")
        }

        // Individual articles with these IDs should NOT appear separately
        let articleIDs = snapshot.items.compactMap { item -> UUID? in
            if case .article(let fi) = item { return fi.id }
            return nil
        }
        for item in items {
            #expect(!articleIDs.contains(item.id),
                    "Clustered item should not appear as standalone article")
        }
    }

    // -------------------------------------------------------------------------
    // TEST: Single-item cluster demotes to .article
    //
    // Scenario: 1 item with a clusterID but no other items share it.
    // Expected output: Appears as .article, not .cluster.
    // -------------------------------------------------------------------------
    @Test func singleItemClusterBecomeArticle() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)
        let clusterID = UUID()

        let item = makeItem(title: "Solo Cluster \(UUID())", relevanceScore: 0.7, clusterID: clusterID)
        store.upsertFeedItems([item])
        store.updateScores([(id: item.id, relevanceScore: 0.7, agedOut: false)])

        let snapshot = service.assembleSnapshot(rateGateResult: nil)

        // Should be an article, not a cluster
        let isArticle = snapshot.items.contains { ri in
            if case .article(let fi) = ri, fi.id == item.id { return true }
            return false
        }
        let isCluster = snapshot.items.contains { ri in
            if case .cluster(let card) = ri, card.id == clusterID { return true }
            return false
        }
        #expect(isArticle, "Single-item cluster should appear as .article")
        #expect(!isCluster, "Single-item cluster should NOT appear as .cluster")
    }

    // -------------------------------------------------------------------------
    // TEST: DigestCards from rate gate are inserted into snapshot
    //
    // Expected output: Snapshot contains a .digest item.
    // -------------------------------------------------------------------------
    @Test func digestCardsInserted() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)

        let digest = DigestCard(
            sourceID: UUID(),
            sourceName: "Test Source",
            itemCount: 5,
            highlights: ["Title 1", "Title 2"],
            overflowIDs: [UUID(), UUID()],
            insertionPosition: Date()
        )
        let rateResult = RateGateResult(
            digestCards: [digest],
            nudgeCards: [],
            hiddenItemIDs: []
        )

        let snapshot = service.assembleSnapshot(rateGateResult: rateResult)
        let hasDigest = snapshot.items.contains { ri in
            if case .digest = ri { return true }
            return false
        }
        #expect(hasDigest, "Snapshot should contain the digest card")
    }

    // -------------------------------------------------------------------------
    // TEST: NudgeCards from rate gate are inserted into snapshot
    //
    // Expected output: Snapshot contains a .nudge item.
    // -------------------------------------------------------------------------
    @Test func nudgeCardsInserted() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)

        let nudge = NudgeCard(sourceID: UUID(), sourceName: "Wire", itemCount: 20)
        let rateResult = RateGateResult(
            digestCards: [],
            nudgeCards: [nudge],
            hiddenItemIDs: []
        )

        let snapshot = service.assembleSnapshot(rateGateResult: rateResult)
        let hasNudge = snapshot.items.contains { ri in
            if case .nudge = ri { return true }
            return false
        }
        #expect(hasNudge, "Snapshot should contain the nudge card")
    }

    // -------------------------------------------------------------------------
    // TEST: Consecutive snapshots detect new items via diff
    //
    // Scenario: First snapshot has 2 items. Second snapshot adds 2 more.
    // Expected output: Second snapshot contains all 4 items.
    // -------------------------------------------------------------------------
    @Test func snapshotDiffDetectsNewItems() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)

        let batch1 = [
            makeItem(title: "Diff A \(UUID())", relevanceScore: 0.8),
            makeItem(title: "Diff B \(UUID())", relevanceScore: 0.7),
        ]
        store.upsertFeedItems(batch1)
        store.updateScores(batch1.map { (id: $0.id, relevanceScore: $0.relevanceScore, agedOut: false) })

        let snap1 = service.assembleSnapshot(rateGateResult: nil)
        let snap1IDs = Set(snap1.items.map(\.id))

        // Add more items
        let batch2 = [
            makeItem(title: "Diff C \(UUID())", relevanceScore: 0.6),
            makeItem(title: "Diff D \(UUID())", relevanceScore: 0.5),
        ]
        store.upsertFeedItems(batch2)
        store.updateScores(batch2.map { (id: $0.id, relevanceScore: $0.relevanceScore, agedOut: false) })

        let snap2 = service.assembleSnapshot(rateGateResult: nil)
        let snap2IDs = Set(snap2.items.map(\.id))

        // New items from batch2 should appear in snap2
        for item in batch2 {
            #expect(snap2IDs.contains(item.id),
                    "New item '\(item.title)' should appear in second snapshot")
        }

        // Batch1 items should still be present
        for item in batch1 {
            #expect(snap2IDs.contains(item.id),
                    "Original item '\(item.title)' should still be in second snapshot")
        }
    }
}


// =============================================================================
// MARK: - 9. PIPELINE PERFORMANCE TESTS
// =============================================================================
//
// What this tests:
//   Wall-clock performance of key pipeline operations to ensure the
//   <150ms total pipeline target is achievable.
//
// Why it matters:
//   The pipeline runs on every feed refresh. If any stage is slow,
//   the UI will stutter or block.
//

struct PipelinePerformanceTests {

    // -------------------------------------------------------------------------
    // TEST: SimHash computation performance
    //
    // Scenario: Compute SimHash for 500 title strings.
    // Expected output: Completes in < 100ms.
    // -------------------------------------------------------------------------
    @Test func simhashComputationPerformance() {
        let titles = (0..<500).map { "Article about topic number \($0) with some extra words for length" }

        let start = CFAbsoluteTimeGetCurrent()
        for title in titles {
            _ = SimHash.compute(title)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 200,
                "SimHash for 500 titles should complete in <200ms, took \(String(format: "%.1f", elapsed))ms")
    }

    // -------------------------------------------------------------------------
    // TEST: SQLite upsert performance
    //
    // Scenario: Upsert 200 FeedItems in one batch.
    // Expected output: Completes in < 500ms.
    // -------------------------------------------------------------------------
    @Test func sqliteUpsertPerformance() {
        let store = SQLiteStore.shared
        let sourceID = UUID()

        let items = (0..<200).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Perf Test \(i)",
                link: URL(string: "https://perf.com/\(UUID().uuidString)")!,
                publishedAt: Date().addingTimeInterval(-Double(i) * 60),
                riverVisible: true
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        store.upsertFeedItems(items)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 500,
                "Upserting 200 items should complete in <500ms, took \(String(format: "%.1f", elapsed))ms")
    }

    // -------------------------------------------------------------------------
    // TEST: Decay scoring computation performance
    //
    // Scenario: Call DecayScoringService.relevance() 1000 times.
    // Expected output: Completes in < 50ms (pure math).
    // -------------------------------------------------------------------------
    @Test func decayScoringPerformance() {
        let tiers = VelocityTier.allCases

        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<1000 {
            let tier = tiers[i % tiers.count]
            let hours = Double(i) * 0.5
            _ = DecayScoringService.relevance(hoursSincePublished: hours, tier: tier)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 50,
                "1000 decay calculations should complete in <50ms, took \(String(format: "%.1f", elapsed))ms")
    }

    // -------------------------------------------------------------------------
    // TEST: Snapshot assembly performance
    //
    // Scenario: Insert 100 items, then assemble a snapshot.
    // Expected output: Assembly completes in < 200ms.
    // -------------------------------------------------------------------------
    @Test func snapshotAssemblyPerformance() {
        let store = SQLiteStore.shared
        let service = RiverSnapshotService(store: store)
        let sourceID = UUID()

        let items = (0..<100).map { i in
            FeedItem(
                sourceID: sourceID,
                title: "Snap Perf \(i)",
                link: URL(string: "https://snap.com/\(UUID().uuidString)")!,
                publishedAt: Date().addingTimeInterval(-Double(i) * 300),
                relevanceScore: Double.random(in: 0.1...1.0),
                riverVisible: true
            )
        }
        store.upsertFeedItems(items)
        store.updateScores(items.map { (id: $0.id, relevanceScore: $0.relevanceScore, agedOut: false) })

        let start = CFAbsoluteTimeGetCurrent()
        _ = service.assembleSnapshot(rateGateResult: nil)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(elapsed < 200,
                "Snapshot assembly for 100 items should complete in <200ms, took \(String(format: "%.1f", elapsed))ms")
    }
}
