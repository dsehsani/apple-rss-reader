# Bug Fix Prompt — Feed Visibility & Content Volume
**Model: `claude-3.7-sonnet`**

---

## Diagnosed Issues (read the code before touching anything)

### Bug 1 — Rate Gate is killing podcast/YouTube/Vimeo content
**Root cause:** `VelocityTier.defaultSlotLimit` in `OpenRSS/Models/VelocityTier.swift`:
- `.evergreen` = **2 items/day** — this is the tier assigned to low-frequency feeds
- `.breaking` = 3, `.news` = 5, `.article` = 8

YouTube channels and podcast feeds post infrequently (weekly or less), so
`VelocityTier.infer(averageItemsPerDay:)` classifies them as `.evergreen`.
Result: **only 2 episodes/videos ever surface per day**, the rest are silently
bundled into DigestCards or hidden. This is why feeds appear to show "nothing"
or only 6 items.

**Fix:** In `OpenRSS/Models/VelocityTier.swift`, raise `.evergreen` slot limit
from 2 to `.max` (unlimited) — evergreen content is rare by definition, capping
it at 2 is never the right behavior. While you're there, also raise `.article`
from 8 to at minimum 15. The user should see all content from a month's window.

```swift
// Before:
case .evergreen: return 2

// After:
case .evergreen: return .max   // same as .essay — rare content, never cap it
```

---

### Bug 2 — Clusters vanish after refresh
**Root cause:** The `RiverSnapshotService` (`OpenRSS/Services/RiverSnapshotService.swift`)
calls `store.fetchRiverItemsAllHistory()` at line 54. A cluster card requires
`clusterItems.count >= 2` (line 71). On the first load, both items in a cluster
are present. After refresh:

1. `DecayScoringService` runs and may mark items as `agedOut = true` if their
   relevance drops below `agedOutThreshold = 0.2`.
2. For `.breaking` tier (half-life 3h), items older than ~15 hours score below 0.2
   and get archived.
3. If the archived item was one of only two in a cluster, the cluster collapses to
   a single-item "cluster" which falls through the `guard clusterItems.count >= 2`
   check and becomes a standalone article — visually disappearing from where the
   cluster card was.

**Fix (two-part):**

Part A — In `OpenRSS/Services/RiverSnapshotService.swift`, change the cluster
minimum from 2 to 1 OR ensure that single-item "orphaned" clusters still appear
as standalone articles (the current `items.append(contentsOf: clusterItems.map
{ .article($0) })` branch should handle this, but verify `fetchRiverItemsAllHistory`
actually returns aged-out items or if it silently drops them).

Part B — Read `OpenRSS/Services/SQLiteStore.swift` and find the
`fetchRiverItemsAllHistory()` implementation. If it filters on `river_visible = 1`
or `aged_out = 0`, that's why the items vanish. The fix is to either:
- Include aged-out items in the history query (let decay opacity handle the visual
  hierarchy, don't hard-exclude them), OR
- Lower `agedOutThreshold` so items decay more slowly

---

### Bug 3 — Feeds showing zero content
**Root cause:** Some newly-added feeds (especially Vimeo Staff Picks, YouTube
channels via RSS) may be fetched successfully but then have ALL items rate-gated
because `RateGateService.applyRateGate()` only processes `todayItems` (items
where `fetchedAt >= startOfDay`). If a feed is added after a pipeline cycle
already ran today, the items land in the store but the snapshot assembler might
be pulling from a stale pre-rate-gate state.

**Fix:** After adding a new feed, trigger a fresh `pipeline.runCycle()` instead
of relying on the 30-minute `autoRefreshIfNeeded` window. Check
`RiverViewModel.refresh()` — it already does this, but confirm the "add feed"
flow calls `refresh()` and not just `autoRefreshIfNeeded()`. Look at
`OpenRSS/ViewModels/AddFeedViewModel.swift` for the post-add hook.

---

### Known Non-Bugs (do NOT fix these in this pass)

- **Vimeo shows no visual difference** — Agent 4 is actively building Vimeo card
  support. Do not touch `ArticleReaderHostView` or add Vimeo detection here.

- **YouTube opens externally** — The `Link(destination: videoURL)` in
  `ArticleReaderHostView.youtubeView()` is intentional for this sprint. The
  YouTube card is a thumbnail + "Watch on YouTube" button that opens the YouTube
  app or Safari. This is expected behavior.

---

## Files to touch (in order)

1. `OpenRSS/Models/VelocityTier.swift` — raise slot limits (Bug 1)
2. `OpenRSS/Services/SQLiteStore.swift` — audit `fetchRiverItemsAllHistory()`
   for `river_visible` / `aged_out` filtering (Bug 2)
3. `OpenRSS/Services/RiverSnapshotService.swift` — verify cluster orphan handling
   (Bug 2)
4. `OpenRSS/ViewModels/AddFeedViewModel.swift` — verify post-add triggers full
   `refresh()` not just scoring (Bug 3)

## Do NOT touch
- `ArticleReaderHostView.swift` (Vimeo/YouTube cards — in-flight from Agent 4)
- `ArticleClusteringService.swift` (clustering algorithm is not the issue)
- `DecayScoringService.swift` (decay math is correct; the threshold may need
  tweaking but only after fixing the slot limits first)

## Success criteria
- A YouTube RSS feed with 10+ videos shows more than 2 in the river
- A podcast feed with weekly episodes shows all episodes within the month window
- Adding a new feed and refreshing shows items immediately
- Clusters do not disappear after a refresh cycle
- Build passes with no errors
