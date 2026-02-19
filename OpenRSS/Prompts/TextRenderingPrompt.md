# RSS Article Pipeline — Claude Code Prompt

I am building an RSS reader app in Swift for iOS using Xcode with iCloud sync via NSPersistentCloudKitContainer. I want you to implement a full article content pipeline. Below are the six phases — implement them in order, and make sure each phase connects cleanly to the next.

---

## Phase 1 — Feed Parsing

Implement an RSS feed parser that:
- Uses URLSession to fetch a feed from a given URL
- Parses both RSS 2.0 and Atom feed formats using XMLParser
- Extracts title, author, pubDate, summary, and link for each item
- Maps results into a struct called `RSSItem` with these fields:
  - `id: UUID`
  - `title: String`
  - `author: String?`
  - `publishDate: Date?`
  - `summary: String?`
  - `sourceURL: URL`
  - `feedName: String`

Create a `RSSParserService` class with a function `fetch(feedURL: URL) async throws -> [RSSItem]`.

---

## Phase 2 — Content Fetching

Implement a content fetching service that:
- Takes an `RSSItem` and fetches the raw HTML from its `sourceURL` using URLSession
- Handles common HTTP errors gracefully
- Returns the raw HTML as a `String`
- Runs asynchronously and is cancellable

Create a `ContentFetcherService` class with a function `fetchHTML(from url: URL) async throws -> String`.

---

## Phase 3 — Content Extraction

Implement a content extraction service using the Readability.js algorithm injected into a hidden, off-screen WKWebView. It should:
- Spin up a `WKWebView` that is never shown to the user
- Load the raw HTML into the WebView
- Inject the Readability.js library (bundle it as a local JS file in the project)
- Call Readability's `parse()` function via `evaluateJavaScript`
- Return the extracted content as a struct called `ReadableContent` with fields:
  - `title: String`
  - `byline: String?`
  - `content: String` (cleaned HTML)
  - `excerpt: String?`
  - `heroImageURL: URL?`
- Tear down the WKWebView after extraction is complete
- Handle failures gracefully with a custom error enum

Create a `ReadabilityExtractionService` class with a function `extract(html: String, sourceURL: URL) async throws -> ReadableContent`.

---

## Phase 4 — Content Normalization

Implement a content normalization service using SwiftSoup that:
- Parses the cleaned HTML from `ReadableContent`
- Walks the DOM and converts it into an array of `ContentNode` enum cases:
  - `heading(level: Int, text: String)`
  - `paragraph(text: String)`
  - `image(url: URL, caption: String?)`
  - `blockquote(text: String)`
  - `list(items: [String], ordered: Bool)`
  - `codeBlock(text: String)`
- Strips any remaining scripts, ads, or irrelevant tags
- Preserves inline links within paragraphs as part of the text

Add SwiftSoup via Swift Package Manager. Create a `ContentNormalizerService` class with a function `normalize(content: ReadableContent) throws -> [ContentNode]`.

---

## Phase 5 — Template Rendering

Implement a SwiftUI article reader view with a templated layout:

- **Header zone:** hero image (if present, loaded async), feed source name and favicon, title, author, date, and estimated read time calculated from word count
- **Body zone:** a ScrollView that iterates the `[ContentNode]` array and renders each node using a dedicated sub-view:
  - `HeadingView` for heading nodes
  - `ParagraphView` for paragraph nodes with tappable inline links
  - `ArticleImageView` for image nodes with async loading and caption below if present
  - `BlockquoteView` for blockquote nodes
  - `ListItemsView` for list nodes
  - `CodeBlockView` for codeBlock nodes
- **Footer zone:** "Open in Safari" button and a Share button

Name the main view `ArticleReaderView` and have it accept a `[ContentNode]` array and a `ReadableContent` object as inputs. Use consistent typography and spacing that matches a clean reading experience.

---

## Phase 6 — Caching

Implement a caching layer that:
- Sets up a Core Data stack using `NSPersistentCloudKitContainer` for iCloud sync
- Creates a `CachedArticle` Core Data entity with attributes for: `id (UUID)`, `title`, `author`, `publishDate`, `heroImageURL`, `feedName`, `sourceURL`, `cachedAt (Date)`, and `serializedNodes (Data — JSON encoded [ContentNode])`
- Creates an `ArticleCacheService` with:
  - `func save(article: ExtractedArticle) throws`
  - `func load(id: UUID) throws -> ExtractedArticle?`
  - `func isCached(id: UUID) -> Bool`
  - `func purgeOldCache(olderThan days: Int) throws`
- Makes `ContentNode` Codable so it can be JSON serialized into Core Data
- Ensures the iCloud container entitlement is configured correctly

The cache should be the first thing checked before triggering phases 2–4. If a cached version exists, skip straight to phase 5.

---

## General Requirements

- All services should be injectable and testable (use protocols where appropriate)
- All async work should use Swift's async/await
- Handle all errors gracefully with descriptive custom error enums
- Organize each phase into its own Swift file
- Once all phases are implemented, wire them together into a single `ArticlePipelineService` with a function `process(item: RSSItem) async throws -> ExtractedArticle` that orchestrates the full flow
    
    
