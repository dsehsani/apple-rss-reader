# iOS RSS Reader App - SwiftUI Implementation

I need you to help me build a beautiful iOS RSS reader app in SwiftUI that embraces Apple's Liquid Glass aesthetic with translucent materials, similar to Apple News.

## Design Reference
I have an HTML/CSS UI schematic from Google Stitch in my project directory that shows the visual design. Please review it first to understand the layout, spacing, colors, and overall aesthetic before proceeding.

## Technical Requirements

### Platform & Architecture
- **Target:** iOS 17+
- **Framework:** SwiftUI with modern Swift 6 concurrency
- **Architecture:** MVVM (Model-View-ViewModel) pattern
- **State Management:** @Observable (iOS 17+ modern approach)
- **Data:** Mock data only - no actual RSS parsing yet (using FeedKit later)

### Design Philosophy
- Embrace Apple's Liquid Glass Display aesthetic
- Use native iOS materials (.ultraThinMaterial, .regularMaterial, .thickMaterial)
- Translucent, frosted glass backgrounds with depth
- Smooth, subtle animations (spring physics)
- SF Symbols throughout
- Clean, spacious layouts with generous padding
- Follow Apple's Human Interface Guidelines

## App Structure

### Bottom Tab Navigation (5 tabs)
1. **Today** (house.fill) - Main feed with category selector
2. **Discover** (sparkles) - Featured content & recommendations  
3. **Saved** (bookmark.fill) - Bookmarked articles
4. **Sources** (folder.fill) - Feed & category management
5. **Settings** (gearshape.fill) - App preferences

### Key Features to Implement

#### Today Tab
- Horizontal scrolling category chips below nav bar
- Categories: "All Updates", "Work", "Tech News", "Design", "Personal"
- Selected chip: filled with accent color, bold text
- Badge counts showing unread articles
- Vertical scrolling article cards with:
  - Source icon + name + timestamp
  - Hero image (16:9 aspect ratio)
  - Title (2 lines max)
  - Excerpt (2-3 lines)
  - Footer with read time + action buttons
- Swipe actions: bookmark, share, mark as read
- Pull to refresh

#### Sources Tab
- Expandable/collapsible category sections
- Each category shows feed count + unread count
- Feed list items (when expanded) with icons
- Floating "+" button (bottom right) for adding feeds
- Swipe to delete/edit feeds
- "Manage Categories" option
- Search functionality

#### Saved Tab
- Similar layout to Today but without category selector
- Filter/sort options

#### Discover Tab
- Featured section (larger cards)
- Trending section (horizontal scroll)
- Recommended sources

#### Settings Tab
- Grouped list style
- Appearance, Reading, Data, Advanced sections

### Mock Data Requirements
Create realistic mock data including:
- 4-5 categories with varying article counts
- 10-15 different RSS sources with names and placeholder icons
- 30-50 mock articles with:
  - Titles, excerpts, timestamps (varying from minutes to weeks ago)
  - Read/unread states
  - Bookmark states
  - Different sources
  - Placeholder images (can use SF Symbols or color blocks)
- Unread counts per category and source

## Development Workflow

### Step 1: Project Structure
**Before writing any code**, please:
1. Analyze the HTML/CSS schematic I've provided
2. Propose a clean folder/file structure following MVVM best practices
3. Ask me to confirm the structure before proceeding
4. Suggest which folders/files to create and where to place them

Example structure to consider (but please optimize):
```
RSSReader/
├── Models/
├── ViewModels/
├── Views/
│   ├── Today/
│   ├── Discover/
│   ├── Saved/
│   ├── Sources/
│   ├── Settings/
│   └── Components/
├── Services/
└── Utilities/
```

### Step 2: Implementation Order
After structure is confirmed, implement in this order:
1. Core Models (Article, Source, Category)
2. Mock data service
3. ViewModels with @Observable
4. Reusable UI Components (ArticleCard, CategoryChip, etc.)
5. Individual tab views
6. Main app structure with TabView

### Step 3: File Creation
For each file you create:
1. **Tell me the exact file name and directory path** before showing code
2. Wait for confirmation that I've created the file
3. Then provide the complete code for that file
4. Explain any important design patterns or SwiftUI techniques used

Example:
```
📁 Please create this file:
Path: RSSReader/Models/Article.swift

[Wait for confirmation, then provide code]
```

## Code Quality Standards

### Swift/SwiftUI Best Practices
- Use Swift 6 modern concurrency (@Observable, not ObservableObject)
- Leverage SwiftUI property wrappers appropriately
- Extract reusable components
- Keep views small and focused (single responsibility)
- Use ViewModifiers for reusable styling
- Proper separation of concerns (MVVM)
- No force unwrapping (use proper optionals)
- Comprehensive comments for complex logic

### Design System Consistency
- Define reusable color, spacing, and typography constants
- Consistent corner radius values
- Standardized shadows and materials
- Unified animation timings
- SF Symbols exclusively for icons

### Naming Conventions
- Views: `TodayView`, `ArticleCardView`, `CategoryChipView`
- ViewModels: `TodayViewModel`, `SourcesViewModel`
- Models: `Article`, `Source`, `Category`
- Clear, descriptive variable names

## Liquid Glass Aesthetic Requirements

### Materials
- Tab bar: `.ultraThinMaterial`
- Nav bars: `.ultraThinMaterial`  
- Article cards: `.regularMaterial` with subtle shadows
- Modal sheets: `.regularMaterial`
- Overlays: `.thickMaterial`

### Visual Effects
- Blur backgrounds behind overlays
- Vibrancy effects on text over materials
- Layering for depth (cards floating above background)
- Subtle gradients where appropriate
- Proper dark mode support (automatic)

### Animations
- Spring physics: `.spring(response: 0.3, dampingFraction: 0.8)`
- Card interactions: scale(0.98) on press
- Smooth transitions between states
- Category switching: crossfade with slide
- All animations ≤ 0.3s duration
- Subtle haptic feedback (where appropriate)

### Spacing & Layout
- Edge margins: 16pt
- Card padding: 16pt
- Between cards: 16pt
- Section spacing: 24pt
- Corner radius: 12pt (standard), 16pt (large)

## Questions & Adaptability

Before you begin:
1. Review the HTML/CSS schematic
2. Ask any clarifying questions about:
   - Specific design details from the schematic
   - Any ambiguous layout decisions
   - Feature prioritization if scope seems large
3. Propose the file structure for my approval
4. Suggest any improvements or best practices I should consider

## Future-Proofing

Keep in mind this is UI-only with mock data. The code should be:
- **Easily adaptable** for real RSS parsing later (FeedKit integration)
- **Protocol-based** where it makes sense (for dependency injection)
- **Testable** (ViewModels should be independent of Views)
- **Modular** (easy to swap mock service for real service)

## Your Approach

Please:
1. ✅ Review HTML/CSS schematic first
2. ✅ Propose file structure and wait for confirmation
3. ✅ Implement step-by-step, one file at a time
4. ✅ Explain design decisions as you go
5. ✅ Ask questions when you need clarification
6. ✅ Suggest improvements based on SwiftUI best practices
7. ✅ Ensure code is clean, well-commented, and follows MVVM strictly

Let's build something beautiful! 🚀
