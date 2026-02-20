# OpenRSS

A native iOS RSS reader built with Swift and SwiftUI, featuring a polished liquid glass UI design with adaptive light/dark mode support.

## Project Overview

OpenRSS is an RSS feed reader app with a hybrid architecture:

- **Free tier**: Local RSS fetching, SwiftData persistence, and optional iCloud sync
- **Premium tier (planned)**: Cloud backend with AWS for advanced web scraping, AI-powered summaries, and real-time updates

---

## Feature Status

| Feature | Status |
|---------|--------|
| Tab-based navigation (Today, Discover, My Feeds, Sources, Settings) | ✅ Done |
| Liquid glass UI with Apple News-style animated tab bar | ✅ Done |
| Adaptive light / dark mode | ✅ Done |
| Article card feed with category chip filtering | ✅ Done |
| Search across articles (liquid glass search bar) | ✅ Done |
| Filter sheet (Saved, Unread, Today) | ✅ Done |
| Bookmark / save articles | ✅ Done |
| Share articles via iOS share sheet | ✅ Done |
| Pull-to-refresh | ✅ Done |
| **Auto-refresh on launch (30-min staleness guard)** | ✅ Done |
| **Local article cache (JSON, 7-day window)** | ✅ Done |
| **Live RSS / Atom feed parsing (FeedKit)** | ✅ Done |
| **In-app article reader (structured, no WebView)** | ✅ Done |
| **YouTube RSS feed support** | ✅ Done |
| **SwiftData persistence (feeds & folders)** | ✅ Done |
| **Add / delete feeds and folders** | ✅ Done |
| **Feed URL validation & title auto-fetch** | ✅ Done |
| Settings UI (appearance, reading, data) | ✅ Done |
| Discover page | ✅ Done |
| Sources view with expandable categories | ✅ Done |
| iCloud sync | 🔲 Not started |
| Push notifications | 🔲 Not started |
| Cloud backend (AWS) | 🔲 Not started |
| AI summaries | 🔲 Not started |

---

## Architecture

The project follows **MVVM** with a protocol-based service layer:

```
SwiftData (SQLite) ──► SwiftDataService  ──► TodayViewModel ──► TodayView
                       (FeedDataService)      MyFeedsViewModel    MyFeedsView
                                              SourcesViewModel    SourcesView

Live RSS fetch ──► RSSService / FeedKit ──► SwiftDataService.refreshAllFeeds()
                   YouTubeAtomParser                │
                   YouTubeService                   ▼
                                          ArticleCacheStore (JSON)
                                          (7-day rolling cache)

Article tap ──► ArticleReaderHostView
                ArticlePipelineService  (fetch → parse → normalize → render)
                ContentFetcherService
                ReadabilityExtractionService
                ContentNormalizerService
                ArticleReaderView  (structured SwiftUI blocks)
```

### Key Design Decisions

- **`FeedDataService` protocol** — `MockDataService` and `SwiftDataService` both conform; swap implementations without touching ViewModels.
- **`ArticleCacheStore`** — thin static JSON cache (3 methods: `save`, `load`, `clear`). Migration path to SQLite/GRDB is a one-file swap.
- **`Article: Codable`** — compatible with both the JSON cache and future SQLite/GRDB codegen.
- **YouTube support** — `YouTubeService` resolves any channel URL format to an Atom RSS URL; `YouTubeAtomParser` (SAX) fills the gaps FeedKit leaves in `media:group` parsing.
- **Article reader** — runs a full extraction pipeline (fetch full page → Readability parse → normalize to `ContentNode` tree → render block-by-block in SwiftUI). Falls back to `excerpt` if the pipeline fails.

---

## Tech Stack

| Technology | Usage |
|------------|-------|
| **Swift** | Primary language |
| **SwiftUI** | Declarative UI framework |
| **SwiftData** | Local persistence for feeds and folders |
| **@Observable** | ViewModel state (Swift 5.9 Observation) |
| **FeedKit** | RSS / Atom / JSON Feed parsing |
| **Foundation XMLParser** | YouTube `media:group` SAX parsing |
| **SF Symbols** | All iconography |
| **iOS 18+** | Minimum deployment target |

### Swift Package Dependencies

| Package | Purpose |
|---------|---------|
| **FeedKit** | RSS, Atom, and JSON Feed XML parsing |

---

## Project Structure

```
OpenRSS/
├── OpenRSSApp.swift                   # App entry point, ModelContainer setup
├── AppState.swift                     # Global app state
│
├── Models/
│   ├── Article.swift                  # Article domain model (Identifiable, Hashable, Codable)
│   ├── Category.swift                 # Folder/category domain model
│   ├── Source.swift                   # RSS source domain model
│   ├── FeedModel.swift                # SwiftData @Model for feed subscriptions
│   ├── FolderModel.swift              # SwiftData @Model for folders
│   ├── CachedArticle.swift            # SwiftData @Model for extracted article cache
│   ├── ContentNode.swift              # Structured article content tree node
│   ├── ReadableContent.swift          # Output of Readability extraction
│   ├── ExtractedArticle.swift         # Pipeline extraction result
│   └── RSSItem.swift                  # Intermediate RSS parse result
│
├── ViewModels/
│   ├── TodayViewModel.swift           # Today feed: filtering, refresh, auto-refresh
│   ├── MyFeedsViewModel.swift         # Feed/folder CRUD and display logic
│   ├── AddFeedViewModel.swift         # Add-feed form: URL validation, title fetch, YouTube resolution
│   ├── SourcesViewModel.swift         # Sources tab state
│   └── SearchViewModel.swift          # Search strategy (title-only / full-text)
│
├── Views/
│   ├── MainTabView.swift              # Liquid glass animated tab bar
│   ├── Today/
│   │   └── TodayView.swift            # Article feed, glass header, category chips
│   ├── MyFeeds/
│   │   ├── MyFeedsView.swift          # Folder + feed list with swipe-to-delete
│   │   ├── AddFeedView.swift          # Add feed / folder sheet
│   │   └── FolderRowView.swift        # Expandable folder row
│   ├── Discover/
│   │   └── DiscoverView.swift         # Featured, trending, recommended sources
│   ├── Sources/
│   │   └── SourcesView.swift          # Source management
│   ├── Settings/
│   │   └── SettingsView.swift         # Appearance, reading, data settings
│   ├── ArticleReader/
│   │   ├── ArticleReaderHostView.swift # Pipeline orchestrator + YouTube card
│   │   ├── ArticleReaderView.swift     # Renders ContentNode tree
│   │   ├── ArticleImageView.swift      # Hero / inline image blocks
│   │   ├── HeadingView.swift           # H1–H6 blocks
│   │   ├── ParagraphView.swift         # Paragraph blocks
│   │   ├── BlockquoteView.swift        # Blockquote blocks
│   │   ├── CodeBlockView.swift         # Code blocks
│   │   ├── ListItemsView.swift         # Ordered / unordered list blocks
│   │   └── TableView.swift             # Table blocks
│   └── Components/
│       ├── ArticleCardView.swift        # Tappable article card with bookmark + share
│       ├── CategoryChipView.swift       # Category filter chips
│       ├── SourceRowView.swift          # Source row + category section header
│       ├── LiquidGlassSearchBar.swift   # Animated glass search bar
│       └── LiquidGlassFilterSheet.swift # Bottom sheet filter panel
│
├── Services/
│   ├── SwiftDataService.swift          # @Observable singleton: SwiftData CRUD + RSS refresh
│   ├── MockDataService.swift           # Mock data (FeedDataService conformance)
│   ├── RSSService.swift                # Network fetch + FeedKit parse
│   ├── RSSParserService.swift          # RSS parse utilities
│   ├── YouTubeService.swift            # Channel URL → RSS URL resolution, thumbnail helpers
│   ├── YouTubeAtomParser.swift         # SAX parser for media:group fields FeedKit misses
│   ├── ArticleCacheStore.swift         # JSON file cache (7-day rolling window)
│   ├── ArticleCacheService.swift       # SwiftData extracted article cache CRUD
│   ├── ArticlePipelineService.swift    # Orchestrates fetch → extract → normalize
│   ├── ContentFetcherService.swift     # Downloads full article HTML
│   ├── ReadabilityExtractionService.swift # Readability-style main content extraction
│   └── ContentNormalizerService.swift  # HTML → ContentNode tree
│
└── Utilities/
    ├── DesignSystem.swift              # Design tokens: colors, typography, spacing, animations
    ├── FilterOption.swift              # FilterOption enum (Saved, Unread, Today)
    └── SearchFilter.swift             # Search filter strategies
```

---

## Setup & Installation

### Prerequisites

- **Xcode 16+**
- **iOS 18.0+** deployment target
- macOS with Apple Silicon or Intel (for Simulator)

### Steps

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd OpenRSS
   ```

2. Open the project:
   ```bash
   open OpenRSS.xcodeproj
   ```

3. Xcode will automatically resolve the **FeedKit** Swift Package dependency on first open.

4. Select a signing team under **Signing & Capabilities** (required for device builds; not needed for Simulator).

5. Press **Cmd + R** to build and run.

### Notes

- Select an **iPhone 16** simulator (or any iOS 18+ device/simulator)
- Supports both **light and dark mode**
- On first launch the feed list is empty — add feeds via the **My Feeds** tab

---

## How It Works

### Adding a Feed

1. Open **My Feeds → +**
2. Paste any RSS/Atom URL, or a YouTube channel URL (any format: `/@handle`, `/channel/UCxxx`, `/c/name`, `/user/name`)
3. The app validates the URL, auto-fetches the feed title, and saves the subscription via SwiftData
4. Optionally assign the feed to a folder

### Today Feed Lifecycle

```
App launch
  │
  ├─ SwiftDataService.configure()
  │    ├─ loadFromSwiftData()      → feeds & folders from SQLite
  │    └─ ArticleCacheStore.load() → articles from JSON cache (instant, no network)
  │
  └─ TodayView.task
       └─ TodayViewModel.autoRefreshIfNeeded()
            ├─ skip if last refresh < 30 min ago
            └─ SwiftDataService.refreshAllFeeds()
                 ├─ fetch + parse each feed via FeedKit
                 ├─ YouTube feeds: supplement with YouTubeAtomParser
                 ├─ update in-memory articles
                 └─ ArticleCacheStore.save() → persist for next launch
```

### Article Reader Pipeline

```
Tap article card
  └─ ArticlePipelineService.run()
       ├─ ContentFetcherService     → download full article HTML
       ├─ ReadabilityExtractionService → extract main content
       ├─ ContentNormalizerService  → HTML → ContentNode tree
       └─ ArticleReaderView         → render blocks in SwiftUI
            (paragraphs, headings, images, blockquotes, code, lists, tables)

YouTube articles → skip pipeline → show video card with thumbnail + description
```

---

## Roadmap

1. **iCloud sync** — CloudKit to sync subscriptions and read state across devices
2. **SQLite article persistence** — Replace `ArticleCacheStore` (JSON) with GRDB for full-text search and richer queries
3. **Notification support** — Background refresh + push notifications for new articles
4. **Premium cloud backend** — AWS infrastructure for web scraping, AI article summaries, and server-side RSS aggregation
