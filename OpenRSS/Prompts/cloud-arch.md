# Cloud Architecture Defined v2

# OpenRSS — Cloud Architecture

**Version:** 2.0
**Date:** April 29, 2026
**Authors:** Josh Bang, Darius Ehsani
**Status:** Approved for Development

---

## Overview

OpenRSS is built around a single guiding principle: **RSS is free and open, and the app experience should reflect that.**

The free vs. premium line is drawn not by artificial feature caps, but by infrastructure cost. Everything that runs on the user's device is free — unlimited, uncapped, and unthrottled. Everything that requires our cloud to exist — integrations, non-RSS sources, and the AI Discovery Agent — is part of the Premium tier.

Free users never feel restricted in their RSS experience. Premium users are buying access to a cloud layer that genuinely extends what's possible beyond RSS.

---

## Product Philosophy

> 💡 **Free = on-device. Premium = cloud.**
> 

The cloud layer exists to solve three problems that on-device RSS fundamentally cannot:

1. **N×M polling** — every device polling every feed independently is unsustainable at scale and gets the app blocked by feed servers
2. **BGTask unreliability** — iOS controls when background refresh fires; guaranteed 5-minute refresh is impossible without a server
3. **Per-device extraction** — every user running a full article extraction independently is wasteful; the first person to open a popular article should pay the cost, not every person

These are infrastructure problems, not feature problems. That is what Premium buys.

---

## Tier Overview

### 🆓 Free — Full Local RSS Experience

Zero calls to our cloud. We incur no marginal cost per free user.

| Feature | Detail |
| --- | --- |
| Feed subscriptions | Unlimited — RSS, Atom, JSON Feed, YouTube |
| River Pipeline | Full on-device — dedup, semantic clustering, velocity tiers, affinity scoring |
| Discovery | On-device catalog search via NLEmbedding |
| Claude Discovery Agent | 5 queries/month (free preview) |
| Sync | iCloud via CloudKit (Apple's infrastructure, not ours) |
| Article extraction | WKWebView + Readability.js on-device |
| Article cache | 7-day local SQLite |

> The 5 free Discovery Agent queries exist because each call costs real Claude API compute. Everything else is free because it costs us nothing.
> 

---

### ⭐ Premium — $5.99/mo or $49.99/yr

Cloud features that require infrastructure we operate and pay for on the user's behalf.

| Feature | Detail |
| --- | --- |
| Priority refresh | Guaranteed 5-minute polling via server-side scheduler + APNs silent push |
| Instant article extraction | Shared cloud extraction cache — most articles return in ~80ms instead of 2–20 seconds |
| Non-RSS integrations | Reddit, GitHub, Substack, Slack, Discord — normalized to the same feed item format |
| Discovery Agent (unlimited) | Full Claude-powered natural language feed discovery, personalized by affinity |
| AI article summaries | On-demand via Claude Haiku, aggressively cached |

---

### 🏅 Founding Member — $3.99/mo or $29.99/yr

Available for the first 6 months post-launch only. Rate locked for 24 months, after which standard pricing applies with 90 days notice. Rewards early adopters without permanently underpricing heavy users.

---

## Cloud Architecture Definition

The OpenRSS cloud layer is a **serverless, event-driven backend** built entirely on AWS managed services. It is designed around three core constraints:

- **Scales to zero** — no idle infrastructure cost when there is no activity
- **Horizontally scalable** — feed polling, extraction, and AI features all fan out across parallel workers with no single-function bottlenecks
    
    [https://www.notion.so](https://www.notion.so)
    
- **Additive to the client** — the iOS app's existing pipeline (River Pipeline, SQLiteStore, ArticlePipelineService) is unchanged; the cloud is a new source of data that slots into existing interfaces

The backend exposes a small REST API secured by short-lived JWTs issued after StoreKit 2 receipt validation. Free users make zero calls to this API. Premium users call it on app open, on silent push receipt, and on demand for article extraction and AI features.

---

## Cloud Architecture Components

### 1. Authentication & Entitlement Layer

StoreKit 2 handles in-app purchase and subscription management on-device. A Lambda function validates receipts server-side and issues a short-lived JWT (24-hour expiry). Every cloud API call includes this JWT — the backend never trusts client-reported tier.

```
User subscribes via StoreKit 2
  → App sends receipt to auth-validate-receipt Lambda
  → Lambda validates with Apple, writes tier to DynamoDB users table
  → Returns signed JWT (24hr expiry)
  → JWT stored securely in Keychain
  → All cloud calls include JWT in Authorization header
  → CloudAuthService silently refreshes when < 2hr remain
```

**New iOS files required:**

- `StoreKitService.swift` — product fetch, purchase flow, Transaction.updates listener
- `CloudAuthService.swift` — receipt → JWT Lambda → Keychain storage and silent refresh

---

### 2. Feed Polling Engine

The core Premium feature. Enables guaranteed 5-minute refresh — something iOS BGTask alone cannot deliver.

**Why fan-out is required:** A single Lambda function has a 15-minute execution timeout. With tens of thousands of unique feed URLs across all subscribers, a single poller would time out. The solution is an orchestrator that distributes work across up to 1,000 parallel worker Lambdas via SQS.

```
EventBridge (every 5 min) → orchestrator Lambda
  → queries Aurora for feeds due for refresh
  → writes each feed URL as a message to SQS queue

SQS → worker Lambdas (auto-scales, up to 1,000 concurrent)
  → each worker fetches one feed via conditional GET (ETag / Last-Modified)
  → diffs new items against what is already in Aurora
  → writes only genuinely new items to feed_items table
  → fires APNs silent push to all subscribers of that feed
```

**Conditional GET** — each worker sends ETag and Last-Modified headers from the previous fetch. If the feed has not changed, the server returns 304 Not Modified and the worker does zero work and writes zero rows. This is the primary cost control on polling.

**New iOS files required:**

- `CloudFeedSyncService.swift` — calls GET /v1/river, receives FeedItem delta, writes to SQLiteStore

---

### 3. APNs Silent Push Delivery

When the feed poller writes new items to Aurora, it immediately fires an APNs silent push (`content-available: 1`, no visible notification) to every subscriber of that feed.

iOS receives the silent push, briefly wakes the app, and CloudFeedSyncService fetches the delta. New articles are in local SQLite before the user opens the app — this is what makes the "5-minute refresh" promise real.

```
feed-poller writes new items to Aurora
  → checks user_feeds for subscribers of that feed
  → fires APNs silent push to each subscriber's registered device token
  → device wakes, calls GET /v1/river?since=timestamp
  → new items available in TodayView within seconds of publication
```

Device tokens are stored in a dedicated DynamoDB table supporting multiple tokens per user (iPhone + iPad).

---

### 4. Shared Article Extraction Cache

**Why Lambda cannot run Puppeteer:** The Puppeteer binary including Chromium is ~180–200MB. AWS Lambda has a 250MB deployment package limit. Additionally, Lambda cold starts with Puppeteer take 3–8 seconds — longer than the on-device path this cache is meant to replace.

**The fix — thin Lambda proxy + warm ECS pool:**

```
Device → API Gateway → extraction-cache Lambda
  → DynamoDB lookup (urlHash → s3Key)
  → HIT:  return cached ContentNode JSON from S3 (~80ms)
  → MISS: push URL to SQS → ECS Fargate extraction worker
          → Puppeteer fetches and renders article
          → Readability.js extracts ContentNode array
          → Store in S3 (72hr lifecycle), index in DynamoDB
          → Return result to device (~3–6s, paid only once per article)
```

After the first user extracts an article, every subsequent user gets the cached result in ~80ms regardless of total user count. The ECS service maintains a warm Puppeteer pool — no cold starts, no package size limits.

**Cache hit rate target:** > 80% for popular articles within the first hour of publication.

**On-device pipeline integration** — a single new L0 check is added at the top of `ArticlePipelineService` before its existing cache layers:

```
L0: GET /v1/extractions/{sha256} → cloud cache (~80ms) [NEW]
L1: NSCache in-memory (existing)
L2: SwiftData disk cache (existing)
L3: WKWebView + Readability.js on-device (existing, fallback only)
```

---

### 5. Integration Adapter Layer

Each non-RSS integration is a standalone Lambda function that fetches from its source and outputs FeedItem-compatible JSON to Aurora. The iOS client sees no difference between an RSS article and a Slack message — they arrive as identical FeedItem records.

| Integration | Method | Cadence |
| --- | --- | --- |
| Reddit | Per-user OAuth + Reddit API relay | Every 10 min |
| GitHub | REST API, public repos (no OAuth required) | Every 10 min |
| Substack | AWS SES forwarding address → Lambda parser | On email receipt |
| Slack | OAuth + webhook listener | Real-time |
| Discord | OAuth + polling | Every 5 min |
| JSON APIs | User-configured field mapping, cloud polling | Configurable |
| Web scraper | Scheduled Lambda, synthesizes feed from HTML | Every 30–60 min |

**Implementation order:** Reddit → GitHub → Substack → Slack → Discord

**Key note on Reddit:** Per-user OAuth tokens are required (not a shared app token) — Reddit API terms of service mandate this.

**Key note on Substack:** Each user receives a unique `@openrss.com` forwarding address derived from a hash of their Apple user ID. Newsletters forwarded to this address are parsed and surfaced as feed items.

---

### 6. AI Discovery Agent

The Discovery Agent runs in three tiers — cheapest first, escalating only when needed.

**Tier 1 — On-Device (Free & Premium, ~0ms)**

- User query → NLEmbedding vector
- Matched against locally cached Feed Catalog JSON (hosted on S3, refreshed weekly)
- Re-ranked by source affinity scores from SQLiteStore
- Returns instantly, zero network call

**Tier 2 — Cloud Index (Premium, ~300ms)**

- Lambda queries DynamoDB feed index (~10,000+ curated feeds, pre-embedded)
- Merges with Tier 1 results, re-ranks by affinity
- Covers niche topics not in local catalog

**Tier 3 — Claude Agent (Premium, ~2–4s)**

- Triggered when Tier 1 + 2 produce weak confidence results, or for ambiguous queries
- Claude Haiku parses intent, validates feed quality, explains recommendations
- Result cached in DynamoDB with 72-hour TTL — same query from any user hits cache, not Claude

```
Query: "something like Hacker News but for design"
  → Tier 1: local catalog match (instant)
  → confidence low → Tier 2: DynamoDB cloud index (~300ms)
  → still weak → Tier 3: Claude Haiku agent (~2–4s)
  → result merged, ranked by affinity, returned to user
```

**Free users:** capped at 5 Tier 3 queries/month, enforced server-side via DynamoDB atomic increment.
**Premium users:** unlimited Tier 3 queries, logged for cost monitoring.

---

### 7. AI Article Summaries

On-demand article summaries via Claude Haiku. Results are cached aggressively by content hash — identical articles are never re-summarized regardless of how many users request them.

- Summary includes key points, estimated read time, and sentiment signal
- 72-hour cache TTL in DynamoDB
- Delivered via `GET /v1/summaries/{sha256}`
- Surfaced in a summary card within ArticleReaderView

---

### 8. Read / Bookmark State Sync

**The problem this solves:** Without a single source of truth, a Premium user reading an article on their iPad would cause CloudKit to sync that read state to their iPhone — but the cloud backend has no record of it. The next `/v1/river` delta call would return that article as unread, and the device, trusting the server, would mark it unread locally. The article would literally un-read itself.

**The fix:**

- **Premium users:** cloud backend is the source of truth for `isRead` / `isBookmarked` state on individual articles. State is written via `POST /v1/state` and returned in every `/v1/river` response.
- **Free users:** CloudKit exclusively handles all state sync.
- **CloudKit remains enabled for all users** for folders, feed subscription lists, and user preferences — things that change infrequently and do not require real-time accuracy.

---

## Database Schema

### Aurora PostgreSQL (Relational Data)

Used for all data that requires joins — feed items, user subscriptions, and read state.

```sql
-- One row per unique feed URL, shared across all users
feed_registry (
  feed_url          TEXT PRIMARY KEY,
  etag              TEXT,
  last_modified     TEXT,
  last_fetched_at   TIMESTAMPTZ,
  subscriber_count  INT DEFAULT 0,
  velocity_tier     TEXT
)

-- Shared article store — one row per article, not per user
feed_items (
  id              UUID PRIMARY KEY,
  feed_id         UUID REFERENCES feeds(id),
  title           TEXT NOT NULL,
  link            TEXT NOT NULL,
  published_at    TIMESTAMPTZ NOT NULL,
  fetched_at      TIMESTAMPTZ NOT NULL,
  excerpt         TEXT,
  image_url       TEXT,
  audio_url       TEXT,
  author          TEXT,
  velocity_tier   TEXT NOT NULL,
  INDEX           (feed_id, published_at DESC)
)

-- Maps users to their subscribed feeds
user_feeds (
  user_id   TEXT NOT NULL,
  feed_id   UUID NOT NULL,
  added_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, feed_id)
)

-- Per-user read/bookmark state
user_item_state (
  user_id        TEXT NOT NULL,
  item_id        UUID NOT NULL,
  is_read        BOOLEAN DEFAULT FALSE,
  is_bookmarked  BOOLEAN DEFAULT FALSE,
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, item_id)
)
```

### DynamoDB (Key-Value Data)

Used for simple, high-speed lookups that do not require joins.

| Table | Key | Purpose |
| --- | --- | --- |
| `users` | userId | Auth tier enforcement (tier, expiresAt) |
| `device-tokens` | userId | APNs silent push token storage |
| `extraction-index` | urlHash | Extraction cache pointer → S3 key |
| `ai-result-cache` | queryHash | Claude result deduplication (72hr TTL) |
| `feed-index` | feedId | Discovery Agent Tier 2 vector index |

---

## API Contract

All endpoints require `Authorization: Bearer <JWT>` except `/v1/auth/validate`.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| POST | `/v1/auth/validate` | Sends StoreKit receipt, returns JWT (24hr expiry) |
| POST | `/v1/devices/register` | Registers APNs device token for silent push |
| GET | `/v1/river?since={epoch}` | Returns FeedItem delta + per-item read/bookmark state |
| POST | `/v1/state` | Syncs isRead / isBookmarked for item IDs |
| GET | `/v1/extractions/{hash}` | Returns cached article ContentNode JSON |
| GET | `/v1/discovery?q={query}` | Discovery Agent (Tier 2 + Tier 3) |
| GET | `/v1/summaries/{hash}` | AI article summary (Claude Haiku, cached) |
| POST | `/v1/affinity` | Uploads source affinity scores for personalization |

Free users call zero endpoints. Premium users have access to all.

---

## Infrastructure Stack Overview

| Component | Service | Reason |
| --- | --- | --- |
| Auth / JWT issuance | AWS Lambda + API Gateway | Stateless, scales to zero |
| Feed polling orchestration | AWS Lambda + EventBridge | Scheduled, serverless |
| Feed polling workers | AWS Lambda + SQS | Fan-out, auto-scales to 1,000 concurrent |
| Feed data (relational) | Aurora Serverless v2 (PostgreSQL) | Join queries, scales to zero when idle |
| Auth / cache data (key-value) | DynamoDB | Simple lookups, low latency, atomic increments |
| Article extraction | ECS Fargate + warm Puppeteer pool | No cold starts, no package size limits |
| Extraction content store | S3 + DynamoDB index | Cheap storage, 72hr TTL lifecycle policy |
| Feed catalog (local sync) | S3 static JSON | Pennies per month to host |
| APNs push delivery | AWS SNS → APNs | Per-notification pricing, no idle cost |
| AI summaries + Discovery Agent | Claude Haiku via Anthropic API | Cheapest capable model |
| Integration adapters | AWS Lambda (one per integration) | Isolated, independently deployable |
| Email ingestion (Substack) | AWS SES + Lambda | Newsletter-to-feed pipeline |

---

## Cost Estimates

### Per-User Monthly Cost

| User Type | Estimated Cloud Cost |
| --- | --- |
| Free user | $0.00 |
| Premium — light usage | $0.30 – $0.60 |
| Premium — heavy AI usage | $1.20 – $2.50 |
| Premium net revenue (after ~22% Apple cut) | ~$4.67/mo |

**Margin is healthy at scale.** Even the heaviest AI user costs ~$2.50 to serve against ~$4.67 net revenue.

### Key Cost Controls

**Extraction cache** — after the first user extracts an article, every subsequent request is served from S3 at ~$0.000004/request. Claude API and Puppeteer compute are bounded by unique article count, not user count.

**AI result cache** — Discovery Agent and summary results are cached by content hash with a 72-hour TTL. Common queries are served from cache > 80% of the time. Effective Claude API cost per user is a fraction of raw API pricing.

**Conditional GET on feed polling** — feeds that have not changed since the last poll return 304 Not Modified. Worker Lambda does zero work and writes zero rows. This is the primary cost control on polling infrastructure.

### Fixed Infrastructure Costs

| Item | Monthly Cost | Notes |
| --- | --- | --- |
| ECS Fargate extraction service (1 warm task) | ~$15/mo | Can scale to zero below ~100 Premium subscribers |
| Aurora Serverless v2 | Scales to zero | Charges per ACU-second of activity only |
| DynamoDB | Pay per request | No provisioned capacity needed |
| S3 (feed catalog + extraction store) | < $5/mo | Static JSON + article content with 72hr TTL |

**Budget alerts** are configured at $50 / $100 / $200/month on AWS to catch unexpected cost spikes early.

---

## Implementation Phases

| Phase | Scope | Timeline |
| --- | --- | --- |
| **Phase 1 — Auth & Entitlement** | StoreKit 2, JWT Lambda, DynamoDB users table, free-tier query counter | Weeks 1–2 |
| **Phase 2 — Merge & Stabilize** | Merge flow-arch branch into main, resolve pipeline conflicts | Weeks 3–4 |
| **Phase 3 — Feed Polling Engine** | Aurora schema, orchestrator + SQS + worker Lambdas, river-sync endpoint, CloudFeedSyncService, APNs | Weeks 5–8 |
| **Phase 4 — Extraction Cache** | ECS Fargate Puppeteer pool, extraction-cache Lambda, S3 + DynamoDB index, ArticlePipelineService L0 | Weeks 9–10 |
| **Phase 5 — Integration Adapters** | Reddit → GitHub → Substack → Slack → Discord | Weeks 11–14 |
| **Phase 6 — AI Features** | AffinitySyncService, Discovery Agent Tier 2 + 3, article summaries, summary card in ArticleReaderView | Weeks 15–18 |

> **Phase 6 should not start until subscription revenue is flowing from Phase 1.**
> 

---

## Known Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| feed_items table grows unboundedly | Medium | 30-day TTL on Aurora feed_items to match on-device retention |
| JWT expiry mid-session | Low | Silent refresh when < 2hr remain; explicit error state if refresh fails |
| SwiftData store wipe on migration failure | **High** | Export to OPML before wipe via existing OPMLService; show recovery UI |
| Reddit API cost at scale | Medium | Per-user OAuth required by Reddit ToS; consider usage cap per user/month |
| Substack forwarding ToS conflicts | Low | Surface as beta, monitor for domain blocks |
| Founding member tier underpricing | Medium | Hard 6-month cap, 24-month rate lock with 90-day change notice in ToS |
| Premium + iCloud state conflict | Resolved | Cloud is source of truth for item state; CloudKit handles folders/subscriptions only |

---

## Open Questions

1. **CloudKit migration on upgrade** — How do we handle existing users who have CloudKit read state when they upgrade to Premium? A one-time migration from CloudKit to our backend is needed on first Premium sign-in.
2. **Feed subscription sync** — When a Premium user subscribes to a new feed, how does the client notify the cloud to begin polling it? A dedicated `POST /v1/feeds` endpoint, or piggybacked onto the next `/v1/river` call?
3. **Multi-device APNs** — A user with an iPhone and iPad should both receive silent push. The device-tokens table stores multiple tokens per user. How do we handle token invalidation on uninstall/reinstall?
4. **ECS cold start** — If the ECS extraction task scales to zero overnight, the first article extraction of the morning takes 20–30s for ECS to boot. Acceptable UX, or do we keep one task warm at all times (~$15/month fixed)?
5. **Founding member cutoff date** — What is the hard date to close founding member pricing? Recommendation: 6 months post-App Store launch.

---

## What We Are Not Building (v1)

- No web app or cross-platform version — iOS only
- No server-side River Pipeline — clustering, decay, and affinity scoring stay on-device
- No social features — no shared feeds, following, or public profiles
- No newsletter forwarding for free users — Premium only
- No real-time WebSocket delivery — APNs silent push is sufficient at this scale