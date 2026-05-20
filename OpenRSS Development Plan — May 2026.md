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
- **Region**: `us-west-2` (matches the deployed `openrss-chat` service in `payam-chat/serverless.yml`). The earlier draft of this doc said `us-east-1` for Aurora pricing reasons; that's moot now that v1 uses DynamoDB + Lambda end-to-end and there's no cross-region cost lever.
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

### Storage — DynamoDB

The v1 polling backend uses DynamoDB instead of Aurora. Subscriber counts will start in the low thousands and the registry in the low hundreds of feeds; that's well inside DynamoDB's comfort zone and skips the VPC/connection-pooling/schema-migration overhead Aurora would impose. The schema below is the same shape as the Postgres design, just modelled for DynamoDB's key + GSI primitives.

**`payam-feed-registry`** — one row per unique feed URL.

| Key | Type | Notes |
|---|---|---|
| `feedUrl` (PK) | S | Canonicalised: lowercase scheme + host, `https://` upgraded from `http://` |
| `feedId` | S | First 32 hex chars of sha256(feedUrl); reused as PK in items table |
| `etag`, `lastModified` | S | For conditional GET |
| `lastFetchedAt`, `lastItemAt`, `createdAt` | N | epoch seconds |
| `velocityTier` | S | `breaking` / `news` / `article` / `essay` / `evergreen` |
| `subscriberCount` | N | Atomic `ADD subscriberCount ±1` from the feeds endpoint |
| `isDead` | BOOL | Set after 3 consecutive 5xx/timeouts; retried once per 24h |
| `consecutiveFailures` | N | Reset on any 2xx/304 |
| `title`, `description`, `imageURL` | S | Cached from last parse |

**`payam-feed-items`** — one row per article. 30-day TTL via DynamoDB native TTL attribute.

| Key | Type | Notes |
|---|---|---|
| `feedId` (PK) | S | Same value as in `payam-feed-registry` |
| `link` (SK) | S | Article URL — the natural dedup key |
| `itemId` | S | Deterministic UUID (FNV-1a) so server and device produce matching IDs for cloud-delivered items |
| `title`, `excerpt`, `author`, `imageURL`, `audioURL`, `videoURL` | S | |
| `publishedAt`, `fetchedAt` | N | epoch seconds |
| `velocityTier` | S | Denormalised from registry to skip a read on delta sync |
| `ttl` | N | `fetchedAt + 2592000` — DynamoDB TTL handles deletion |

GSI **`feedId-fetchedAt-index`** (PK `feedId`, SK `fetchedAt`, full projection) powers the `/v1/river` delta-sync query "items since X for this feed".

**`payam-user-feeds`** — per-user subscriptions. PK `userId`, SK `feedUrl`. Stores `feedId` denormalised and `folderName`, `addedAt`.

**`payam-user-item-state`** — premium-only read/bookmark state. PK `userId`, SK `itemId`. Free users keep CloudKit.

**Orchestrator query strategy.** With < ~10K feeds, the orchestrator runs a full `Scan` with a velocity-tier filter every 5 min — at on-demand pricing this is ~$1.50/month, and a GSI keyed on velocity tier would create a hot-partition problem (only 5 distinct PK values). When the registry exceeds ~50K rows, migrate to a bucketed GSI or split the scan across multiple invocations.

**When to revisit.** Move to Aurora when (a) registry > 50K feeds, (b) full-text search becomes a hard requirement for Discovery Tier 2 (see Phase 5), or (c) cross-feed analytical queries appear in product requirements. None of these is blocking at v1.

### Polling architecture

```
EventBridge (every 5 min)
  → orchestrator Lambda
    → Scan payam-feed-registry, filter rows whose
      polling_interval(velocityTier) has elapsed
      (also retry rows where isDead = true && lastFetchedAt < now - 24h)
    → SendMessageBatch one entry per due feed → payam-poll-queue

SQS → worker Lambdas (concurrent, reservedConcurrency 50, one feed per msg)
  → conditional GET (If-None-Match / If-Modified-Since)
  → 304: UpdateItem lastFetchedAt, done
  → 200: parse feed, BatchWriteItem with attribute_not_exists(link) for dedup
    → UpdateItem on registry (etag, lastModified, lastFetchedAt, velocityTier)
    → for each subscriber: push APNs silent notification (stub — iOS follow-up)
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
GET /v1/river?since={epochSec}
Authorization: Bearer <JWT>

Response:
{
    "items": [FeedItem],        // new items since timestamp
    "state": [ItemState],       // read/bookmark state changes (premium only)
    "deleted": [UUID],          // items expired or removed (empty until tombstones land)
    "serverTime": epochSec      // client stores this for next sync
}
```

Implementation:

1. Query `payam-user-feeds` by `userId` → list of `feedId`s.
2. Fan out parallel Queries against `feedId-fetchedAt-index` (`fetchedAt > since`), `Limit: 100` per feed, descending.
3. Merge + cap to 500 items.
4. If premium, `BatchGetItem` `payam-user-item-state` for the returned `itemId`s and merge into the response.

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
  → ArticlePipelineService checks L0: GET /v1/extractions/{sha256(url)}?url=...
    → Cache HIT  → presigned S3 URL → device fetches JSON (~80ms total)
    → Cache MISS → Lambda fetches the page synchronously, runs jsdom +
                   @mozilla/readability inline, writes to S3 + DynamoDB,
                   returns the same {contentUrl, cachedAt} shape (1–3s)
    → 422 not_extractable → device falls back to existing L1/L2/L3 pipeline
```

No SQS extraction queue, no Fargate, no 202+retry dance. The cache miss path is a single synchronous Lambda invocation that fits inside the 28s API Gateway HTTP API timeout.

### Infrastructure

| Component | Service | Config |
|---|---|---|
| Extract Lambda | Lambda (Node.js 20) | 1024 MB, 28s timeout, jsdom + @mozilla/readability bundled |
| Content storage | S3 (`payam-extractions`) | 72-hour lifecycle, blocked public access, presigned GETs (10-min TTL) |
| Cache index | DynamoDB `payam-extraction-index` | `urlHash` → `{s3Key, cachedAt, extractedHost, ttl}` (native TTL) |

### JS-heavy sites

The Lambda runs `jsdom`, which parses static HTML and runs no JavaScript. SPA-heavy sites (~20% of articles) will fail the quality gate (`length < 500 chars` or empty title) and receive `422 not_extractable`. The iOS client treats this as a signal to fall back to its existing L3 pipeline: WKWebView loads the live URL, JS renders, on-device Readability.js extracts. **No regression vs today** — those articles already take 2–20s on-device.

Server-side JS rendering (Fargate + Puppeteer) is a future upgrade, justified only by usage data showing the SPA gap is a real user complaint.

### Client-side

One change to `ArticlePipelineService.swift`: add L0 cloud check before the existing L1 (NSCache), L2 (SwiftData), L3 (WKWebView) layers. Premium users check cloud first. On HIT or MISS-extracted the device fetches the JSON, runs the existing `ContentNormalizerService.normalize()` on the returned HTML to produce `[ContentNode]`, and caches the result in L1/L2 so re-opens stay instant. On 422 the device runs the existing L3 path unchanged. Free users skip L0 entirely.

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

> **Storage caveat for v1.** The feed registry lives in DynamoDB (see Phase 3), which has no native full-text search. Tier 2 is therefore not buildable as written without one of: (a) deferring Tier 2 until an Aurora migration; (b) projecting the registry into OpenSearch via DynamoDB streams; (c) shipping Tier 1 + Tier 3 only and treating Tier 2 as a v2 feature. Decide before Phase 5 starts. The rest of this section describes the Aurora-backed design as a target architecture.

Search against `feed_registry`. Every feed that any premium user has ever subscribed to is in this table, with live quality signals.

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

Each adapter is a standalone Lambda that writes `FeedItem`-shaped rows directly into `payam-feed-items` (with a synthesised `feedId` per source — e.g. `reddit:<subreddit>`, `github:<owner>/<repo>`). The client sees no difference — these items enter the same delta-sync pipeline as RSS items.

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
| API Gateway | AWS API Gateway HTTP API | ~$1.00/million requests |
| Auth + sync + polling Lambdas | AWS Lambda | ~$0.20/million invocations |
| Feed data (registry + items + user-feeds + user-item-state) | DynamoDB on-demand | ~$5–15 at v1 scale |
| Extraction Lambda + jsdom workload | AWS Lambda | ~$1–3 per 100K extractions (1024 MB, ~1–3s each) |
| Auth/cache data | DynamoDB | ~$1-5 on-demand |
| Extraction storage | S3 (72hr TTL) | <$1 |
| Push notifications | SNS → APNs | Free (APNs is free, SNS is ~$0.50/million) |
| AI discovery | Claude Haiku | ~$0.01-0.03/query |
| AI summaries | Claude Haiku | ~$0.005/summary |

Per premium user at steady state, the simpler v1 stack lands well under the original Aurora-plus-Fargate envelope — roughly $0.20–0.50/month light usage, $1.00–2.20 heavy AI usage. Aurora and Fargate re-enter the cost table only when (a) the feed registry exceeds ~50K rows and an Aurora migration becomes necessary, or (b) usage data shows server-side JavaScript rendering for the cache is justified.

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
