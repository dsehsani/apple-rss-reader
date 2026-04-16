# OpenRSS Phase 2 — Agent Implementation Brief

**For:** ClaudeIDE coding agent
**Project:** OpenRSS iOS (SwiftUI, MVVM, iOS 17+)
**Scope:** River Architecture + Source Affinity Layer

---

## Existing Codebase — What's Already There

Do not recreate these. Build on them.

- `Services/RSSService.swift` — feed fetching (keep YouTube logic, migrate general fetch to `FeedIngestService`)
- `Services/ArticlePipelineService.swift` — pipeline shell, no stage logic yet; replace with `RiverPipeline.swift`
- `Services/SwiftDataService.swift` — current persistence; replace with `SQLiteStore.swift` for pipeline tables only. Keep SwiftData for user prefs/settings.
- `ViewModels/TodayViewModel.swift` — replace with `RiverViewModel.swift`; port its category-filter logic
- `Views/Today/TodayView.swift` — update to render `RiverItem` union type
- `Views/Components/ArticleCardView.swift` — add opacity modifier + dwell time tracking
- `Views/Settings/SettingsView.swift` — add Source Affinity section
- `Models/Source.swift` — add `velocityTier: VelocityTier` and `defaultSlotLimit: Int`
- `OpenRSSApp.swift` — add `BGTaskScheduler` registration

---

## New Files to Create (in dependency order)

```
Services/SQLiteStore.swift
Services/FeedIngestService.swift
Services/SemanticClusterService.swift
Services/RateGateService.swift
Services/DecayScoringService.swift
Services/RiverSnapshotService.swift
Services/RiverPipeline.swift
Services/AffinityTracker.swift
Models/FeedItem.swift
Models/RiverItem.swift
Models/ClusterCard.swift
Models/DigestCard.swift
Models/NudgeCard.swift
Models/InteractionEvent.swift
Models/SourceAffinityRecord.swift
ViewModels/RiverViewModel.swift
Views/Today/ClusterCardView.swift
Views/Today/DigestCardView.swift
Views/Today/NudgeCardView.swift
Views/Settings/SourceAffinityView.swift
```

---

## SQLite Schema (WAL mode — run once on DB open)

```sql
PRAGMA journal_mode = WAL;

CREATE TABLE feed_items (
    id               TEXT PRIMARY KEY,
    source_id        TEXT NOT NULL,
    title            TEXT NOT NULL,
    link             TEXT NOT NULL,
    published_at     INTEGER NOT NULL,   -- Unix timestamp
    fetched_at       INTEGER NOT NULL,
    cluster_id       TEXT,
    is_canonical     INTEGER DEFAULT 0,
    velocity_tier    TEXT NOT NULL,      -- 'breaking'|'news'|'article'|'essay'|'evergreen'
    relevance_score  REAL DEFAULT 1.0,
    aged_out         INTEGER DEFAULT 0,
    river_visible    INTEGER DEFAULT 1,
    simhash_value    INTEGER,
    embedding_vector BLOB                -- serialized [Float] 512-dim; NULL until computed
);

CREATE TABLE source_affinity (
    source_id      TEXT PRIMARY KEY,
    affinity_score REAL DEFAULT 0.0,    -- clamped [-0.3, 1.0]
    event_count    INTEGER DEFAULT 0,
    last_updated   INTEGER,
    velocity_tier  TEXT,
    slot_limit     INTEGER
);

CREATE TABLE interaction_events (
    id         TEXT PRIMARY KEY,
    source_id  TEXT NOT NULL,
    item_id    TEXT NOT NULL,
    event_type TEXT NOT NULL,
    timestamp  INTEGER NOT NULL,
    dwell_time REAL
);

CREATE INDEX idx_feed_items_source ON feed_items(source_id, fetched_at);
CREATE INDEX idx_feed_items_river  ON feed_items(river_visible, relevance_score);
CREATE INDEX idx_events_source     ON interaction_events(source_id, timestamp);
```

---

## Data Models

### FeedItem
```swift
struct FeedItem {
    let id:              String
    let sourceID:        String
    let title:           String
    let link:            URL
    let publishedAt:     Date
    let fetchedAt:       Date
    var clusterID:       String?
    var isCanonical:     Bool
    var velocityTier:    VelocityTier
    var relevanceScore:  Double
    var agedOut:         Bool
    var riverVisible:    Bool
    var simhashValue:    UInt64
    var embeddingVector: [Float]?       // 512-float NLEmbedding; nil until Pass 2 runs
}
```

### RiverItem
```swift
enum RiverItem: Identifiable {
    case article(FeedItem)
    case cluster(ClusterCard)
    case digest(DigestCard)
    case nudge(NudgeCard)

    var id: String { ... }
    var positionalWeight: Double { ... }
}
```

### ClusterCard
```swift
struct ClusterCard {
    let clusterID:     String
    let canonicalItem: FeedItem
    let sourceCount:   Int
    let sourceNames:   [String]
    let allItemIDs:    [String]
}
```

### DigestCard
```swift
struct DigestCard {
    let sourceID:          String
    let sourceName:        String
    let itemCount:         Int
    let highlights:        [String]   // 2–3 title snippets
    let overflowIDs:       [String]
    let insertionPosition: Date
}
```

### InteractionEvent
```swift
struct InteractionEvent {
    let id:        UUID
    let sourceID:  String
    let itemID:    String
    let eventType: InteractionEventType
    let timestamp: Date
    let dwellTime: TimeInterval?
}

enum InteractionEventType: String {
    // Tier 1 — strong
    case articleOpen, sourceBrowse, digestExpand, clusterExpand, articleShare
    // Tier 2 — medium
    case dwellLong, dwellMedium, scrollSlow, returnVisit
    // Tier 3 — negative
    case quickBounce, scrollFastPast, explicitDismiss
}
```

### SourceAffinityRecord
```swift
struct SourceAffinityRecord {
    let sourceID:      String
    var affinityScore: Double       // clamped [-0.3, 1.0]
    var eventCount:    Int
    var lastUpdated:   Date
    var velocityTier:  VelocityTier
    var slotLimit:     Int
}
```

### VelocityTier
```swift
enum VelocityTier: String {
    case breaking, news, article, essay, evergreen
    
    var halfLifeHours: Double {
        switch self {
        case .breaking:  return 3
        case .news:      return 18
        case .article:   return 48
        case .essay:     return 168
        case .evergreen: return 720
        }
    }
    
    var lambda: Double { log(2) / halfLifeHours }
}
```

---

## Five-Stage Pipeline

All stages run on a background actor. Only Stage 5's Combine emit crosses to main actor. Full cycle must complete in **< 150ms** for 500 items.

### Stage 1 — FeedIngestService
- Conditional GET using `ETag` / `Last-Modified` headers; skip unchanged feeds
- Parse XML/Atom → `FeedItem` structs
- Deduplicate by `guid` against SQLite (`feed_items.id`)
- Assign `fetchedAt` and `sourceID`
- Delegate YouTube Atom parsing to existing `RSSService`

### Stage 2 — SemanticClusterService (three passes)

**Pass 1 — SimHash on title tokens (run on all items)**
```swift
func simhash(_ text: String) -> UInt64 {
    let tokens = text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { $0.count > 2 }
    var vector = [Int](repeating: 0, count: 64)
    for token in tokens {
        let hash = fnv1a(token)             // use FNV-1a, not Swift .hashValue (non-deterministic)
        for bit in 0..<64 {
            vector[bit] += (hash >> bit) & 1 == 1 ? 1 : -1
        }
    }
    return vector.enumerated().reduce(UInt64(0)) { r, p in
        p.element > 0 ? r | (1 << p.offset) : r
    }
}
// Candidate if hammingDistance(a, b) <= 3
func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
```

**Pass 2 — NLEmbedding on candidates only (title + description ≤ 200 chars)**
- Only run on: (a) Pass 1 candidate pairs, (b) items within 6-hour window with no Pass 1 match but temporal proximity
- Use `NLEmbedding.sentenceEmbedding(for: .english)` — no custom CoreML model needed
- Cosine similarity threshold: **≥ 0.82**
- Store 512-float vector in `embeddingVector` field; keep only for 6-hour active window

```swift
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    let dot  = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}
```

**Pass 3 — NER entity overlap on Pass 2 survivors**
- Use `NLTagger(tagSchemes: [.nameType])` on title + description excerpt
- Tags: `.personalName`, `.placeName`, `.organizationName`
- Confirm cluster if **≥ 2 shared entities**

**Cluster resolution:**
- Assign shared `clusterID` to grouped items
- Canonical item = earliest published, OR source with `affinityScore > 0.5` (if any in cluster)
- Non-clustered items: `clusterID = nil`
- Cluster window: last 6 hours only

### Stage 3 — RateGateService

Default daily slot limits per source type:
| Source Type | Limit |
|---|---|
| Breaking news / wire | 3/day |
| General news | 5/day |
| Tech/topic blogs | 8/day |
| Personal blogs / newsletters | unlimited |
| Podcast / video | 2/day |

- Count `river_visible` items per `source_id` for current calendar day
- Items exceeding limit: set `riverVisible = false`, bundle into `DigestCard`
- `DigestCard.insertionPosition` = timestamp of first overflow item
- Extract 2–3 title snippets as `highlights`
- **Flood detection:** if source item count in rolling 2-hour window > `mean + 3σ` of historical baseline → emit `NudgeCard`
- If `affinityScore > 0.7`: `effectiveSlotLimit = min(defaultLimit × 1.5, defaultLimit + 3)`
- If `affinityScore < -0.15`: `effectiveSlotLimit = max(1, defaultLimit - 2)`

### Stage 4 — DecayScoringService

```swift
// Relevance decay
func relevance(hoursSincePublished t: Double, tier: VelocityTier) -> Double {
    exp(-tier.lambda * t)
}

// Affinity boost (sourced from SourceAffinityRecord)
let boost = min(max(source.affinityScore, 0), 0.5)
let adjustedRelevance = relevance * (1.0 + boost)

// Thresholds
// > 0.7  → full opacity, normal weight
// 0.4–0.7 → 60% opacity
// 0.2–0.4 → 35% opacity, reduced font size
// < 0.2  → agedOut = true → archive on next refresh
```

- Items with `agedOut = true` are **not deleted** — move to archive, indexed for full-text search
- Update `positionalWeight` for sort order

### Stage 5 — RiverSnapshotService

- Construct `[RiverItem]` from scored items + `DigestCard`s + `NudgeCard`s
- Diff against previous snapshot using stable `RiverItem.id`s
- Emit delta via `PassthroughSubject<RiverSnapshot, Never>`

---

## RiverViewModel

```swift
@MainActor
class RiverViewModel: ObservableObject {
    @Published var items: [RiverItem] = []

    init() {
        RiverPipeline.shared.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.items = snapshot.items
                }
            }
            .store(in: &cancellables)
    }
}
```

Port `TodayViewModel`'s existing category-filter logic into this class.

---

## Background Task Registration (OpenRSSApp.swift)

```swift
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.openrss.riverRefresh",
    using: nil
) { task in
    Task {
        await RiverPipeline.shared.runCycle()
        task.setTaskCompleted(success: true)
    }
    scheduleNextRefresh()
}
```

Add `com.openrss.riverRefresh` to `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.

---

## Affinity Tracker (AffinityTracker.swift)

EMA update after every interaction event:

```swift
// alpha = 0.15 (fixed)
// Initial score = 0.0 for all sources
// Clamp result to [-0.3, 1.0]
func updateAffinity(current: Double, eventWeight: Double) -> Double {
    let updated = 0.15 * eventWeight + 0.85 * current
    return min(max(updated, -0.3), 1.0)
}
```

Event weights:
| Event | Weight |
|---|---|
| sourceBrowse | +1.2 |
| articleShare | +1.1 |
| articleOpen | +1.0 |
| returnVisit | +0.9 |
| digestExpand | +0.8 |
| dwellLong (>45s) | +0.7 |
| clusterExpand | +0.6 |
| dwellMedium (15–45s) | +0.4 |
| scrollSlow | +0.2 |
| explicitDismiss | -0.5 |
| quickBounce (<5s) | -0.3 |
| scrollFastPast | -0.1 |

Persist to `source_affinity` table asynchronously after each pipeline run.

---

## Dwell Time Tracking (ArticleReaderView.swift)

```swift
.onAppear  { appearedAt = Date() }
.onDisappear {
    guard let appeared = appearedAt else { return }
    let dwell = Date().timeIntervalSince(appeared)
    let eventType: InteractionEventType = dwell < 5 ? .quickBounce
                                        : dwell < 15 ? .articleOpen
                                        : dwell < 45 ? .dwellMedium
                                        : .dwellLong
    AffinityTracker.shared.record(eventType, sourceID: article.sourceID,
                                  itemID: article.id, dwellTime: dwell)
}
```

---

## SwiftData → SQLite Migration

- On first launch: migrate existing `feed_items` from SwiftData → SQLite
- Dual-write during transition build
- Retain SwiftData store as read-only fallback for 30 days post-migration
- SwiftData stays active for: user preferences, settings, non-pipeline data

---

## SourceAffinityView (Settings)

Per-source panel showing:
- Affinity tier label: `Low` (< 0) / `Neutral` (0–0.3) / `Interested` (0.3–0.7) / `Highly Interested` (> 0.7)
- "Reset affinity" button → set `affinityScore = 0.0` for that source
- Global "Reset all reading signals" → clear entire `source_affinity` + `interaction_events` tables

All affinity data is on-device only. No sync. No external analytics.

---

## Build Order (Phase Sequence)

| Phase | Deliverable |
|---|---|
| 2a | SQLiteStore + FeedIngestService + DecayScoringService + decay UI in TodayView + BGTask |
| 2b | SemanticClusterService (all 3 passes) + ClusterCard model + ClusterCardView |
| 2c | RateGateService + DigestCard + DigestCardView + NudgeCardView |
| 2d | AffinityTracker + EMA scoring + Stage 3/4 affinity integration + SourceAffinityView |
