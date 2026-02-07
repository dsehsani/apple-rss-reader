# OpenRSS

A native iOS RSS reader built with Swift and SwiftUI, featuring a polished liquid glass UI design with adaptive light/dark mode support.

## Project Overview

OpenRSS is an RSS feed reader app designed with a hybrid architecture:

- **Free tier**: Local RSS fetching with SwiftData storage and optional iCloud sync
- **Premium tier (planned)**: Cloud backend with AWS for advanced web scraping, AI-powered summaries, and real-time updates

### Key Features

| Feature | Status |
|---------|--------|
| Tab-based navigation (Today, Discover, Saved, Sources, Settings) | Implemented |
| Liquid glass UI with Apple News-style sliding tab bar | Implemented |
| Article card feed with category filtering | Implemented |
| Bookmark/save articles | Implemented |
| Source management with expandable categories | Implemented |
| Search & filter across articles and sources | Implemented |
| Adaptive light/dark mode | Implemented |
| Settings UI (appearance, reading, data) | Implemented |
| Discover page with featured/trending content | Implemented |
| Pull-to-refresh | Implemented |
| RSS feed parsing & live fetching | Not started |
| SwiftData persistence | Not started |
| iCloud sync | Not started |
| In-app article reader / WebView | Not started |
| Share sheet integration | Not started |
| Push notifications | Not started |
| Cloud backend (AWS) | Not started |
| AI summaries | Not started |

## Current Implementation Status

### Working Now

The full **UI/UX layer** is implemented with mock data:

- **5-tab navigation** with a custom liquid glass tab bar that features direct finger-tracking and spring animations
- **Today view**: Scrollable article feed with category chip filtering, search, and pull-to-refresh
- **Discover view**: Featured content, trending topics (horizontal scroll), and recommended sources
- **Saved view**: Bookmarked articles with sort options (date saved, date published, source, read status)
- **Sources view**: Expandable category sections, source search, floating add button, and add-source sheet
- **Settings view**: Grouped settings for appearance, reading preferences, data/storage, and about info
- **Reusable components**: ArticleCardView, CategoryChipView, SourceRowView, CategorySectionHeader
- **Design system**: Centralized design tokens for colors, typography, spacing, shadows, and animations

### In Progress / Stubbed

- Share actions (prints to console)
- Add/delete source (UI exists, no persistence)
- Settings toggles (UI-only, not persisted)
- Clear cache button (no-op)

### Not Started

- RSS/Atom feed parsing and network fetching
- SwiftData models and persistence layer
- iCloud CloudKit sync
- In-app browser / article detail view
- Real notifications
- Cloud backend infrastructure

## Tech Stack

| Technology | Usage |
|------------|-------|
| **Swift** | Primary language |
| **SwiftUI** | UI framework (declarative views) |
| **@Observable** | ViewModel state management (Swift 5.9 Observation framework) |
| **SF Symbols** | All iconography |
| **iOS 18+** | Minimum deployment target |

### Dependencies

**None currently.** The project has no Swift Package Manager dependencies. All UI and logic is built with native Apple frameworks.

Planned dependencies (from tech survey):
- RSS/Atom XML parser (e.g., FeedKit or custom)
- Networking layer for feed fetching
- AWS SDK (premium tier)

## Project Structure

```
OpenRSS/
├── OpenRSSApp.swift              # App entry point
├── Assets.xcassets/              # App icon, accent color
├── Models/
│   ├── Article.swift             # Article data model
│   ├── Category.swift            # Category data model
│   └── Source.swift              # RSS source data model
├── ViewModels/
│   ├── TodayViewModel.swift      # Today feed logic & state
│   ├── SavedViewModel.swift      # Saved articles logic & state
│   └── SourcesViewModel.swift    # Sources management logic & state
├── Views/
│   ├── MainTabView.swift         # Tab bar with liquid glass pill animation
│   ├── Today/
│   │   └── TodayView.swift       # Main feed with glass header & category chips
│   ├── Discover/
│   │   └── DiscoverView.swift    # Featured, trending, recommended sources
│   ├── Saved/
│   │   └── SavedView.swift       # Bookmarked articles with sort options
│   ├── Sources/
│   │   └── SourcesView.swift     # Source management with expandable categories
│   ├── Settings/
│   │   └── SettingsView.swift    # App settings & preferences
│   └── Components/
│       ├── ArticleCardView.swift  # Reusable article card
│       ├── CategoryChipView.swift # Category filter chip + chips row
│       └── SourceRowView.swift    # Source row + category section header
├── Services/
│   └── MockDataService.swift     # Mock data with FeedDataService protocol
├── Utilities/
│   └── DesignSystem.swift        # Design tokens, Color hex extension, view modifiers
└── Prompts/                      # Development prompt files (internal)
```

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

2. Open the project in Xcode:
   ```bash
   open OpenRSS.xcodeproj
   ```

3. Select a signing team under **Signing & Capabilities** (required for device builds).

4. No additional configuration or dependency installation is needed.

## How to Run

1. Open `OpenRSS.xcodeproj` in Xcode
2. Select an **iPhone 16** simulator (or any iOS 18+ simulator/device)
3. Press **Cmd + R** to build and run

### Notes

- The app runs entirely on **mock data** — no network connection is required
- Works on both Simulator and physical devices
- Supports both **light and dark mode** (follows system setting)
- No provisioning profile needed for Simulator builds

## Architecture

The project follows an **MVVM (Model-View-ViewModel)** pattern:

- **Models** (`Article`, `Category`, `Source`): Plain Swift structs conforming to `Identifiable` and `Hashable`
- **ViewModels** (`TodayViewModel`, `SavedViewModel`, `SourcesViewModel`): `@Observable` classes that hold state and business logic
- **Views**: SwiftUI views that bind to ViewModels via `@State`
- **Services**: `FeedDataService` protocol with `MockDataService` implementation — designed for easy swap to a real networking/persistence layer

## Next Steps

1. **RSS feed parsing** — Integrate an XML parser to fetch and parse real RSS/Atom feeds
2. **SwiftData persistence** — Convert models to `@Model` classes for local storage
3. **Article detail view** — In-app WebView or reader mode for full article content
4. **Real networking** — Replace `MockDataService` with a live `FeedDataService` implementation
5. **iCloud sync** — Enable CloudKit for cross-device feed and bookmark sync
6. **Share sheet** — Wire up `UIActivityViewController` for article sharing
7. **Add source flow** — Implement feed URL validation and subscription
8. **Premium tier backend** — AWS infrastructure for web scraping, AI summaries, and push notifications
