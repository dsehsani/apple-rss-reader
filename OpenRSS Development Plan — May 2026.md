# OpenRSS Development Plan

**Date:** May 19, 2026
**Author:** Josh Bang
**Status:** Active

---

## Where we are

The local app has a working 5-stage pipeline: ingest, semantic clustering, rate gating, decay scoring, and snapshot assembly. It handles RSS/Atom/JSON Feed/YouTube, persists to SQLite, syncs subscriptions via CloudKit, and runs background refresh. Tests cover all pipeline stages.

What we don't have: cloud infrastructure, a subscription system, or a way to serve users who need more than what BGTask and on-device processing can reliably deliver.

### What's built and working

| Layer | Status | Notes |
|---|---|---|
| Feed ingest (6 concurrent, conditional GET) | Stable | `FeedIngestService.swift` |
| Semantic clustering (CoreML MiniLM + NLEmbedding fallback) | Stable, needs threshold tuning | `SemanticClusterService.swift` |
| Rate gating (slot limits, digest/nudge cards) | Stable | `RateGateService.swift` |
| Decay scoring (exponential, velocity-tier aware) | Stable | `DecayScoringService.swift` |
| Snapshot assembly (cluster collapse, source interleaving) | Stable | `RiverSnapshotService.swift` |
| SQLite store (WAL mode, feed_items + affinity + events) | Stable | `SQLiteStore.swift` |
| SwiftData (folders, feeds, article state, user profile) | Stable | `SwiftDataService.swift` |
| Sign in with Apple + Keychain | Working | `AuthenticationManager.swift` |
| CloudKit sync (subscriptions, folders, dedup on import) | Working, no conflict resolution | `SyncService.swift` |
| Background refresh (BGAppRefreshTask + BGProcessingTask) | Working, iOS-controlled timing | `OpenRSSApp.swift` |
| Article extraction (WKWebView + Readability.js) | Working, 2-20s per article | `ArticlePipelineService.swift` |
| Discover tab (static catalog) | Working | `DiscoverView.swift` |
| Tests (pipeline, clustering, embeddings, integration) | Passing | 8 test files |

### What's broken or incomplete

| Issue | Severity | Detail |
|---|---|---|
| Entitlements wiped on current branch | High | `feat/pipeline-perf-and-clustering-fix` stripped CloudKit, Sign in with Apple, and APNs entitlements. Main still has them. Must not merge without restoring. |
| 3 unmerged branches with overlapping changes | High | `flow-arch` (6 commits), `nathan-dev` (1 new commit), current branch (2 commits). All touch pipeline files. |
| Dead code in codebase | Low | `TodayViewModel`, `ArticleClusteringService`, `ArticlePipelineService` are replaced but still present. `GeminiService` may be orphaned. |
| No subscription/payment system | N/A | Expected — hasn't been built yet. |
| CloudKit sync has no conflict resolution | Medium | Keeps oldest record on duplicate. Acceptable for folders/feeds, not for article state at scale. |
| SwiftData wipes store on schema migration failure | High | Existing behavior. Needs OPML export guard before any schema changes. |

---

## Branch consolidation

This is the first thing that has to happen. Nothing else can safely proceed while three branches are diverged.

### Merge order

**1. Fix entitlements on current branch**

The current branch (`feat/pipeline-perf-and-clustering-fix`) accidentally deleted all entitlements. Restore from main before merging anything.

```
aps-environment: development
com.apple.developer.applesignin: [Default]
com.apple.developer.icloud-container-identifiers: [iCloud.DariusEhsani.OpenRSS]
com.apple.developer.icloud-services: [CloudKit]
```

**2. Merge `feat/pipeline-perf-and-clustering-fix` into main**

2 commits: CoreML sentence-transformer bundling + test fixes. Low conflict risk.

**3. Merge `flow-arch` into main**

6 commits (all Josh): decay scoring, semantic clustering, river scoring, YouTube filter, search/archive views. High conflict risk in `SemanticClusterService`, `RiverPipeline`, `DecayScoringService`.

Decision required: `flow-arch` uses NLEmbedding. Current branch uses CoreML MiniLM. The CoreML path is faster and more accurate in benchmarks. Recommendation: keep CoreML as primary, NLEmbedding as fallback (which is what the current branch already does).

**4. Cherry-pick Nathan's commit onto main**

`nathan-dev` diverged from Darius's old base. The full diff is -20k lines against current main because it's missing months of work. Do not merge the branch. Cherry-pick `ca6fe6f` (feed search, folder reordering, Spotify detection, user-agent fix, `FeedCatalogService`).

**5. Clean up**

Delete `V1-DEV` (0 commits ahead of main), `awaab-dev` (0 commits ahead), `flow-architecture` (duplicate of `flow-arch`).

---

## Phase 1 — Local app hardening (weeks 1-2)

Cloud integration touches `FeedIngestService`, `ArticlePipelineService`, `AuthenticationManager`, `KeychainService`, and `OpenRSSApp`. These files need to be stable and tested before we modify them.

### Dead code removal

Remove files that are replaced and no longer referenced:

- `TodayViewModel.swift` — replaced by `RiverViewModel`
- `ArticleClusteringService.swift` — replaced by `SemanticClusterService`
- `ArticlePipelineService.swift` — replaced by `RiverPipeline` (but note: cloud extraction L0 cache will need a pipeline service. Rename or repurpose, don't just delete)
- `GeminiService.swift` — verify if `ChatViewModel` still references it. If so, decide: keep Gemini, replace with Claude, or remove chat feature
- `ChatSheetView.swift` + `ChatViewModel.swift` — if Gemini is removed, remove the UI

### Clustering threshold tuning

The CoreML MiniLM embedding provider is bundled but thresholds were set against test fixtures. Run against production-like feed sets:

- 10+ news sources (overlapping stories expected)
- Tech blogs (similar topics, different stories — should NOT cluster)
- Podcasts (unique content, should never cluster)
- Mixed language feeds if we plan to support them

Document the false-positive and false-negative rates. Adjust the 0.72 cosine similarity threshold and SimHash distance of 10 if needed.

### SwiftData migration safety

The app currently wipes the SwiftData store on migration failure. Before any schema changes:

- Add OPML auto-export before store wipe (use existing `OPMLService`)
- Show recovery UI that lets users re-import
- Test the migration path from current schema to the schema with new Premium fields (`subscriptionTierRaw`, `premiumExpiresAt`)

### Test coverage

Current tests cover pipeline stages individually. Add:

- End-to-end test: raw RSS XML in, `RiverSnapshot` out, verify item ordering and cluster grouping
- Regression test for the digest card disappearing bug (reading articles mid-session)
- Performance benchmark: full pipeline cycle time with 500+ items across 50+ sources

---

## Phase 2 — Auth and entitlements (weeks 3-4)

Every cloud feature requires authentication and tier enforcement. This is the gate.

### Server-side

| Component | Service | Work |
|---|---|---|
| Auth endpoint | Lambda + API Gateway | `POST /v1/auth/validate` — accepts StoreKit 2 receipt, verifies with Apple, issues JWT (24hr expiry) |
| User store | DynamoDB `users` table | `userId`, `tier` (free/premium/founding), `expiresAt`, `createdAt` |
| Device registration | Lambda | `POST /v1/devices/register` — stores APNs token for silent push |
| Device store | DynamoDB `device-tokens` table | `userId` → `[{apnsToken, platform, registeredAt}]` (multi-device) |

Infrastructure decisions to make before writing code:

- **IaC tool**: CDK (TypeScript, same language as Lambda code) or Terraform (team familiarity). Pick one, use it for everything.
- **Region**: `us-east-1` (cheapest Aurora Serverless, required for some AWS features) or closest to user base.
- **JWT signing**: RSA or ECDSA. ECDSA is smaller and faster to verify on-device. Use ES256.

### Client-side

| File | Work |
|---|---|
| `StoreKitService.swift` (new) | StoreKit 2 product fetch, purchase flow, `Transaction.updates` listener, receipt extraction |
| `CloudAuthService.swift` (new) | Send receipt to `/v1/auth/validate`, store JWT in Keychain, silent refresh when <2hr remain |
| `KeychainService.swift` (modify) | Add `saveJWT()`, `loadJWT()`, `deleteJWT()` alongside existing Apple user ID methods |
| `UserPreferences.swift` (modify) | Add `subscriptionTierRaw: String`, `premiumExpiresAt: Date?` |
| `OpenRSSApp.swift` (modify) | Wire `StoreKitService` init, APNs registration for premium users |

### Entitlements

The app needs these capabilities enabled in the Xcode project (some already exist on main):

```
aps-environment: development (already on main, needed for silent push)
com.apple.developer.applesignin (already on main)
com.apple.developer.icloud-container-identifiers (already on main)
com.apple.developer.icloud-services: CloudKit (already on main)
com.apple.developer.in-app-purchases (new — required for StoreKit 2)
```

### Validation

- Purchase flow works in sandbox environment
- JWT round-trips correctly (issue on server, store on device, attach to request, verify on server)
- Free users hit zero cloud endpoints
- Premium expiry degrades gracefully to free tier (no crash, no data loss)

---

## Phase 3 — Feed polling engine (weeks 5-8)

This is the core cloud feature. It replaces on-device HTTP polling with server-side polling and delta sync.

### Why this matters for production

On-device polling has three real problems:

1. **BGTask is unreliable.** iOS decides when to run it. Users see stale content when they open the app.
2. **N devices x M feeds = redundant requests.** Every device polls every feed independently. Feed servers rate-limit or block apps that do this at scale.
3. **Battery and data.** Polling 100 feeds on-device every 15 minutes burns battery and cellular data.

Server-side polling solves all three. Each feed URL is fetched once regardless of how many users subscribe. Devices get a delta of new items via a single API call.

### Database schema (Aurora Serverless v2 — PostgreSQL)

```sql
-- Shared feed registry. One row per unique feed URL across all users.
-- The polling engine reads this to know what to fetch and when.
CREATE TABLE feed_registry (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feed_url        TEXT UNIQUE NOT NULL,
    title           TEXT,
    description     TEXT,
    image_url       TEXT,
    etag            TEXT,
    last_modified   TEXT,
    last_fetched_at TIMESTAMPTZ,
    last_item_at    TIMESTAMPTZ,
    subscriber_count INT DEFAULT 0,
    velocity_tier   TEXT NOT NULL DEFAULT 'article',
    category        TEXT,
    -- Discovery agent will use these columns (added now to avoid migration later)
    search_vector   TSVECTOR,
    quality_score   REAL DEFAULT 0.0,
    is_dead         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_feed_registry_due ON feed_registry (last_fetched_at)
    WHERE is_dead = FALSE;
CREATE INDEX idx_feed_registry_search ON feed_registry USING GIN (search_vector);

-- Shared article store. One row per article, not per user.
CREATE TABLE feed_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feed_id         UUID NOT NULL REFERENCES feed_registry(id),
    title           TEXT NOT NULL,
    link            TEXT NOT NULL,
    published_at    TIMESTAMPTZ NOT NULL,
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    content_hash    TEXT,
    excerpt         TEXT,
    image_url       TEXT,
    audio_url       TEXT,
    author          TEXT,
    velocity_tier   TEXT NOT NULL,
    UNIQUE (feed_id, link)
);

CREATE INDEX idx_feed_items_feed_published
    ON feed_items (feed_id, published_at DESC);

-- Per-user feed subscriptions.
CREATE TABLE user_feeds (
    user_id         TEXT NOT NULL,
    feed_id         UUID NOT NULL REFERENCES feed_registry(id),
    folder_name     TEXT,
    added_at        TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, feed_id)
);

-- Per-user article state (read, bookmarked).
-- Only for premium users. Free users use CloudKit.
CREATE TABLE user_item_state (
    user_id         TEXT NOT NULL,
    item_id         UUID NOT NULL REFERENCES feed_items(id),
    is_read         BOOLEAN DEFAULT FALSE,
    is_bookmarked   BOOLEAN DEFAULT FALSE,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, item_id)
);
```

30-day TTL on `feed_items` via scheduled cleanup job. Matches the on-device 30-day cache retention.

### Polling architecture

```
EventBridge (every 5 min)
  → orchestrator Lambda
    → SELECT feed_url FROM feed_registry
      WHERE is_dead = FALSE
      AND last_fetched_at < NOW() - polling_interval(velocity_tier)
    → write each URL to SQS queue

SQS → worker Lambdas (concurrent, one per feed URL)
  → conditional GET (If-None-Match / If-Modified-Since)
  → 304: update last_fetched_at, done
  → 200: parse feed, diff against existing items
    → INSERT new items into feed_items
    → UPDATE feed_registry (etag, last_modified, last_fetched_at, velocity_tier)
    → for each subscriber: push APNs silent notification
```

Polling interval by velocity tier:
- `breaking`: 5 min
- `news`: 15 min
- `article`: 1 hour
- `essay`: 6 hours
- `evergreen`: 24 hours

Dead feed detection: 3 consecutive 5xx or timeout → mark `is_dead = TRUE`. Retry dead feeds once per 24 hours. If a dead feed returns 200, clear the flag.

### Delta sync endpoint

```
GET /v1/river?since={iso8601_timestamp}
Authorization: Bearer <JWT>

Response:
{
    "items": [FeedItem],        // new items since timestamp
    "state": [ItemState],       // read/bookmark state changes
    "deleted": [UUID],          // items that expired or were removed
    "serverTime": "iso8601"     // client stores this for next sync
}
```

The query:

```sql
SELECT fi.*, uis.is_read, uis.is_bookmarked
FROM feed_items fi
JOIN user_feeds uf ON fi.feed_id = uf.feed_id
LEFT JOIN user_item_state uis ON fi.id = uis.item_id AND uis.user_id = $1
WHERE uf.user_id = $1
  AND fi.fetched_at > $2
ORDER BY fi.published_at DESC
LIMIT 500;
```

### Client-side

| File | Work |
|---|---|
| `CloudFeedSyncService.swift` (new) | Call `/v1/river?since=`, convert response to `[FeedItem]`, upsert into `SQLiteStore` |
| `FeedIngestService.swift` (modify) | Add routing: if premium, delegate to `CloudFeedSyncService` instead of direct HTTP fetch |
| `OpenRSSApp.swift` (modify) | On APNs silent push receipt, trigger `CloudFeedSyncService.sync()` |

The pipeline downstream of ingest (clustering, gating, decay, snapshot) is unchanged. Cloud-delivered `FeedItem`s enter at the same point as locally-fetched ones.

### Subscription change sync

When a premium user adds or removes a feed on-device:

```
POST /v1/feeds
{
    "added": [{"feedUrl": "...", "folder": "..."}],
    "removed": [{"feedUrl": "..."}]
}
```

The server upserts into `user_feeds` and increments/decrements `feed_registry.subscriber_count`. If a feed URL is new to the platform, it's added to `feed_registry` and picked up on the next polling cycle.

---

## Phase 4 — Shared extraction cache (weeks 9-10)

### Why this matters

On-device article extraction takes 2-20 seconds per article (WKWebView + Readability.js). For popular articles, every user independently extracts the same content. The extraction cache means the first user pays the cost and everyone after gets it in ~80ms.

### Architecture

```
Device opens article
  → ArticlePipelineService checks L0: GET /v1/extractions/{sha256(url)}
  → Cache HIT: return ContentNode JSON from S3 (~80ms)
  → Cache MISS: return 202, push URL to SQS extraction queue

SQS → ECS Fargate extraction worker (warm Puppeteer pool)
  → fetch page, run Readability.js
  → store ContentNode JSON in S3
  → index in DynamoDB (extraction-index: urlHash → s3Key)
  → device retries after 3-5s, gets cache HIT
```

### Infrastructure

| Component | Service | Config |
|---|---|---|
| Cache proxy | Lambda | Thin: DynamoDB lookup → S3 presigned URL or SQS dispatch |
| Extraction workers | ECS Fargate | 0.5 vCPU, 1GB RAM, Puppeteer + Readability.js |
| Content storage | S3 | 72-hour lifecycle policy |
| Cache index | DynamoDB `extraction-index` | `urlHash` → `{s3Key, cachedAt, ttl}` |
| Extraction queue | SQS | Dedup by urlHash (5-min dedup window) |

Scale: ECS task count driven by SQS queue depth. Minimum 0 (scale to zero overnight), maximum 10. First-morning cold start is ~20-30s — acceptable because the on-device fallback (L1-L3) still works.

### Client-side

One change to `ArticlePipelineService.swift`: add L0 cloud check before the existing L1 (NSCache), L2 (SwiftData), L3 (WKWebView) layers. Premium users check cloud first. Free users skip L0 entirely.

---

## Phase 5 — Discovery agent (weeks 11-14)

### Why build this right after polling, not later

The polling engine populates `feed_registry` with live data: subscriber counts, velocity tiers, last fetch times, dead feed flags. The discovery agent uses this data to rank recommendations. Without it, discovery is searching a static catalog with no quality signals.

The extraction cache enables instant article previews when users browse recommended feeds. Without it, previewing a discovery result means on-device extraction — slow and discouraging.

Building discovery after polling and extraction means users get fast, informed recommendations from day one. Building it before means recommendations are blind and previews are slow.

### Three tiers

**Tier 1 — On-device catalog search (free)**

Already partially built. Nathan's `FeedCatalogService` dynamically fetches the awesome-rss-feeds GitHub catalog and caches it for 24 hours. The existing `DiscoverView` renders categories.

Remaining work:
- Wire `FeedCatalogService` into `DiscoverView` (replace static `RSSCatalog` if Nathan's version is more complete)
- Add NLEmbedding-based semantic search over the catalog (type "machine learning" and get relevant feeds, not just keyword matches)
- This tier works entirely on-device. No cloud cost.

**Tier 2 — Cloud catalog search (premium)**

Search against `feed_registry` in Aurora. Every feed that any premium user has ever subscribed to is in this table, with live quality signals.

```
GET /v1/discovery?q=machine+learning&limit=20
Authorization: Bearer <JWT>

Server-side:
  → full-text search against feed_registry.search_vector
  → rank by: text relevance * quality_score * log(subscriber_count + 1)
  → filter out is_dead = TRUE
  → filter out feeds user already subscribes to
  → return top 20 with title, description, image_url, velocity_tier, subscriber_count
```

`quality_score` is computed from: subscriber count, posting frequency, successful extraction rate, and how often subscribers unsubscribe within 7 days (churn signal).

**Tier 3 — AI-powered discovery (premium, rate-limited)**

For queries that don't match well against existing feeds, or for natural-language requests like "podcasts about the history of computing that update weekly."

```
GET /v1/discovery/ai?q=podcasts+about+history+of+computing+weekly
Authorization: Bearer <JWT>

Server-side:
  → check DynamoDB ai-result-cache (72hr TTL, keyed by query hash)
  → cache HIT: return cached result
  → cache MISS:
    → load user's top affinity categories from source_affinity
    → prompt Claude Haiku with query + affinity context + known feed_registry entries
    → Claude returns structured feed suggestions with URLs
    → verify each URL is a valid RSS feed (HEAD request + content-type check)
    → cache result in DynamoDB
    → return verified suggestions
```

Rate limit: 5 queries/month for free users (preview), unlimited for premium. Counter stored in DynamoDB `users` table.

### The affinity feedback loop

```
User reads articles → affinity scores update in SQLite
  → AffinitySyncService uploads top-N source affinities to cloud
  → Discovery Tier 3 uses affinity to personalize Claude prompt
  → user discovers and subscribes to recommended feed
  → polling engine starts fetching it
  → new articles flow through pipeline
  → affinity scores update
```

This loop only works when polling, extraction, and discovery are all live. It's the product differentiator — personalized feed discovery that gets better the more you use the app.

### Client-side

| File | Work |
|---|---|
| `AffinitySyncService.swift` (new) | Upload top-20 source affinities to cloud on each pipeline cycle |
| `DiscoverView.swift` (modify) | Add search bar that routes to Tier 1 (free) or Tier 2/3 (premium) |
| `DiscoverViewModel.swift` (new) | Manage search state, tier routing, result display |

---

## Phase 6 — Integration adapters (weeks 15-18)

Non-RSS content sources that users want but can't get via standard feed parsing.

Priority order based on user demand and implementation complexity:

| Adapter | Complexity | Notes |
|---|---|---|
| Reddit | Medium | Per-user OAuth required by Reddit ToS. Subreddit → FeedItem conversion. |
| GitHub | Low | Public repos via REST API, no OAuth needed. Releases, issues, activity. |
| Substack | Medium | SES forwarding address → parse email → FeedItem. Newsletter-to-feed. |
| Slack | High | OAuth relay + webhook. Deferred unless user demand is clear. |
| Discord | High | Similar to Slack. Deferred. |

Each adapter is a standalone Lambda that outputs `FeedItem`-compatible JSON to Aurora. The client sees no difference — these items enter the same pipeline as RSS items.

Client-side: add `sourceType` enum cases to `Source.swift`. The pipeline doesn't care about source type — it processes `FeedItem`s identically regardless of origin.

---

## API contract

All endpoints require `Authorization: Bearer <JWT>` except where noted.

| Method | Endpoint | Phase | Purpose |
|---|---|---|---|
| POST | `/v1/auth/validate` | 2 | StoreKit receipt → JWT |
| POST | `/v1/devices/register` | 2 | Register APNs device token |
| GET | `/v1/river?since={ts}` | 3 | Feed item delta + read state |
| POST | `/v1/feeds` | 3 | Subscription changes (add/remove) |
| POST | `/v1/state` | 3 | Sync read/bookmark state |
| GET | `/v1/extractions/{hash}` | 4 | Cached article content |
| GET | `/v1/discovery?q={query}` | 5 | Tier 2 catalog search |
| GET | `/v1/discovery/ai?q={query}` | 5 | Tier 3 AI discovery |
| POST | `/v1/affinity` | 5 | Upload source affinity scores |
| GET | `/v1/summaries/{hash}` | 6+ | AI article summaries (future) |

Free users call zero endpoints. Premium users call all of them.

---

## Infrastructure

| Component | Service | Monthly cost estimate |
|---|---|---|
| API Gateway | AWS API Gateway | ~$3.50/million requests |
| Auth + sync + polling Lambdas | AWS Lambda | ~$0.20/million invocations |
| Feed data | Aurora Serverless v2 (PostgreSQL) | ~$0 idle, ~$50 at moderate load |
| Auth/cache data | DynamoDB | ~$1-5 on-demand |
| Extraction workers | ECS Fargate | ~$15/task/month (scale 0-10) |
| Extraction storage | S3 (72hr TTL) | <$1 |
| Push notifications | SNS → APNs | Free (APNs is free, SNS is ~$0.50/million) |
| AI discovery | Claude Haiku | ~$0.01-0.03/query |
| AI summaries | Claude Haiku | ~$0.005/summary |

Per premium user at steady state: $0.30-0.60/month light usage, $1.20-2.50 heavy AI usage. Premium subscription nets ~$4.67 after Apple's cut. Margins are healthy.

---

## Pricing

| Tier | Price | Access |
|---|---|---|
| Free | $0 | Full local RSS, on-device pipeline, CloudKit sync, Tier 1 discovery, 5 AI discovery queries/month |
| Premium | $5.99/mo or $49.99/yr | Server polling, extraction cache, Tier 2+3 discovery, AI summaries, integration adapters |
| Founding Member | $3.99/mo or $29.99/yr | Same as Premium. Available first 6 months post-launch. Rate locked 24 months. |

The free tier is a complete RSS reader. No artificial limits. Premium solves infrastructure problems that on-device can't: reliable refresh timing, shared extraction, cloud-scale discovery.

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `feed_items` table grows unboundedly | Medium | 30-day TTL via scheduled cleanup |
| SwiftData store wipe on migration | High | Auto-export OPML before wipe, recovery UI |
| JWT expiry mid-session | Low | Silent refresh at <2hr remaining |
| Reddit API cost/ToS | Medium | Per-user OAuth, usage cap |
| ECS cold start after overnight scale-to-zero | Low | Accept 20-30s first extraction; on-device fallback still works |
| Branch merge conflicts | High | Merge this week before any new feature work |
| CloudKit ↔ cloud state divergence for premium users | High | Cloud is source of truth for item state; CloudKit handles folders/subscriptions only |

---

## What we are not building

- No web app or cross-platform client
- No server-side pipeline (clustering, decay, scoring stay on-device)
- No social features (shared feeds, profiles, following)
- No real-time WebSocket delivery (APNs silent push is sufficient)
- No free-tier cloud features beyond the 5 AI discovery queries/month

---

## Open decisions

1. **IaC tooling** — CDK or Terraform? Decide before Phase 2 starts.
2. **Clustering engine final call** — CoreML MiniLM (faster, more accurate in benchmarks) or NLEmbedding (no model bundle size). Recommendation: CoreML primary, NLEmbedding fallback.
3. **ECS warm pool** — Keep 1 task warm ($15/mo) or accept cold start? Can decide after measuring real extraction traffic in Phase 4.
4. **GeminiService** — Keep, replace with Claude, or remove? If the chat feature stays, it should use the same AI provider as the rest of the cloud stack.
5. **Founding member cutoff** — Hard date to close enrollment. Recommendation: 6 months post-App Store launch.
