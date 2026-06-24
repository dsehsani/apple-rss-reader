# All Important Key Features

> Payam is a next-generation RSS reader for iOS that blends traditional feed reading with on-device intelligence, semantic clustering, and an AI agent. This document captures the headline features — **what** each one is, **why** it exists, and **how it differs from the RSS industry standard**.

---

## A. Intelligent River Engine

### 1. Multi-Stage River Pipeline
- **What:** A background pipeline that transforms raw feed items into a personalized, ranked "river": ingest → cluster → rate-gate → decay-score → snapshot.
- **Why:** A single coherent flow that dedupes, groups, rate-limits, scores, and ranks every item before it ever reaches the screen.
- **Differs from RSS standard:** Standard readers show a flat, reverse-chronological list of everything. Payam runs real signal processing over the stream.

### 2. Semantic Cross-Source Clustering
- **What:** Detects when multiple sources are covering the same story and collapses them into a single cluster card (SimHash + on-device embeddings + named-entity recognition, within a 12-hour window).
- **Why:** Surface breaking news once, from multiple angles, instead of flooding the feed with near-duplicates.
- **Differs from RSS standard:** Traditional readers list the same story N times — once per source. Payam shows it once, with the coverage grouped.

### 3. Exponential Decay Scoring & Visual Opacity
- **What:** Time-based relevance decay using velocity-tier-specific half-lives, boosted by source affinity; older items progressively fade in opacity.
- **Why:** Fresh content stays prominent while stale content gracefully ages out — without hiding it entirely.
- **Differs from RSS standard:** RSS treats every unread item as equally important forever. Payam models relevance as a decaying signal.

### 4. Rate Gating & Digest Cards
- **What:** Per-source daily article limits based on publishing velocity; overflow is bundled into a single collapsible "digest" card, with nudge cards explaining when a source is being throttled.
- **Why:** Keep high-volume sources from drowning out everything else, while still preserving access to their overflow.
- **Differs from RSS standard:** Standard readers give a 100-post-a-day firehose the same weight as a once-a-week blog. Payam balances the flow.

### 5. Velocity Tier Classification
- **What:** Each source is auto-classified by publishing cadence (article / stream / firehose), with manual override; this drives slot limits and decay half-lives.
- **Why:** Different sources behave very differently — the system adapts its handling per source.
- **Differs from RSS standard:** Readers don't model per-source publishing cadence at all.

### 6. Source Affinity Learning
- **What:** A local exponential-moving-average of your engagement with each source (reads, bookmarks, dwell time), used to boost favorites in scoring and ranking.
- **Why:** The river quietly learns which sources you actually care about and elevates them.
- **Differs from RSS standard:** Personalization here is **100% on-device** — no cloud analytics, no tracking.

---

## B. AI Capabilities

### 7. Payam Assistant (Action-First Agent)
- **What:** A Claude-backed conversational agent, accessible from the article view, that can answer questions, summarize, recommend feeds, and create filter rules — returning structured, actionable views rather than just text.
- **Why:** Turns a passive feed into a conversational interface you can actually talk to.
- **Differs from RSS standard:** Standard RSS is a dumb aggregator. Payam adds a context-aware AI layer over your feeds.

### 8. AI Article Summary
- **What:** On-demand Claude summarization of the current article, using the fully extracted content.
- **Why:** Pull the key points from a long article in seconds.
- **Differs from RSS standard:** No equivalent exists in traditional RSS readers.

### 9. Natural-Language Filter Rules
- **What:** Describe what you don't want in plain English ("hide opinion pieces," "exclude newsletters") and the agent parses it into a structured, scope-aware predicate (global, per-folder, or per-feed).
- **Why:** A non-technical way to suppress entire content genres without unsubscribing.
- **Differs from RSS standard:** Standard filters are manual keyword/regex rules; Payam infers intent from natural language.

### 10. Agentic Feed Discovery
- **What:** The agent suggests new feeds based on your interests and current subscriptions, deliberately avoiding duplicates.
- **Why:** Smart, conversational discovery of sources you'll actually like.
- **Differs from RSS standard:** Readers offer static directories; Payam reasons about your existing subscriptions.

---

## C. Reading Experience

### 11. Native Structured Article Reader
- **What:** Fetches full article HTML, runs Readability extraction, normalizes it into a typed content-node tree, and renders it natively (paragraphs, images, headings, quotes, code, lists, tables) — no embedded WebView.
- **Why:** Full control over typography and layout, with fast, accessible, native performance.
- **Differs from RSS standard:** Most readers show truncated feed snippets or drop you into a raw in-app browser. Payam renders the whole article natively.

### 12. YouTube-as-RSS & Video / Podcast Handling
- **What:** Subscribe to YouTube channels as feeds (any URL format), with a custom Atom parser, content-type routing (Shorts / Streams / Videos / Premieres), plus Vimeo (oEmbed thumbnails), direct-video, and podcast/audio detection.
- **Why:** Bring rich multimedia sources into the same reading flow as text.
- **Differs from RSS standard:** Goes well beyond basic enclosure handling with first-class, custom multimedia parsing.

### 13. Adaptive Liquid Glass UI
- **What:** A polished, Apple News-style frosted-glass aesthetic with animated transitions, adapting to light/dark mode, built on a centralized design system.
- **Why:** A premium, modern reading environment that feels native to iOS.
- **Differs from RSS standard:** Most readers ship utilitarian list UIs; Payam invests in a distinctive, refined visual design.

---

## D. Architecture & Sync

### 14. Hybrid Cloud + Local Architecture
- **What:** Premium tier pulls from a cloud backend (`/v1/river`, delta sync against server time); basic tier polls RSS directly on-device — with automatic fallback to local polling if the cloud is unavailable.
- **Why:** Combines cloud scalability and pre-computed ranking with offline-first reliability.
- **Differs from RSS standard:** Readers are typically all-cloud *or* all-local. Payam is both, with seamless failover and no duplicate items.

### 15. On-Device Embeddings
- **What:** Sentence embeddings computed locally via a CoreML MiniLM model, with an NLEmbedding fallback, powering the semantic clustering.
- **Why:** Real semantic intelligence without sending your reading to the cloud.
- **Differs from RSS standard:** Standard readers rely on simple keyword matching, if anything; Payam's clustering runs privately on-device.

### 16. Enhanced OPML Import / Export
- **What:** Standard OPML 2.0 import/export of all subscriptions and folders, preserving folder colors and icons via custom `openrss:` attributes.
- **Why:** Easy backup and migration to/from other readers, with no loss of your organization.
- **Differs from RSS standard:** Fully standards-compliant, plus a metadata superset most readers drop.

---

## E. Discovery & Onboarding

### 17. Interactive Action-Detection Onboarding
- **What:** A first-run experience (welcome → interest picker → checklist → celebration) that watches for *real* user actions (create a folder, subscribe, read an article) to complete its checklist, and seeds Discover ordering from chosen interests.
- **Why:** Teach key actions by doing, boost retention, and personalize from the very first session.
- **Differs from RSS standard:** It's action-driven, not a passive static walkthrough.

### 18. Affinity-Weighted Discover
- **What:** A Discover tab with Featured, Categories, and Recommended sections, where recommendations are weighted by learned affinity and onboarding interests.
- **Why:** Help users find great sources tailored to what they actually read.
- **Differs from RSS standard:** Discovery adapts to your behavior rather than serving a fixed directory.

---

## Summary — How Payam Stands Apart

| Dimension | Standard RSS Reader | Payam |
|---|---|---|
| Feed order | Flat reverse-chronological | Multi-stage ranked river |
| Duplicate stories | Listed N times | Clustered into one card |
| Item relevance | All-equal, forever | Decay-scored over time |
| High-volume sources | Flood the feed | Rate-gated + digested |
| Personalization | None / cloud-tracked | On-device affinity learning |
| Intelligence | Keyword search | AI agent + on-device embeddings |
| Article body | Snippet / WebView | Native structured render |
| Architecture | All-cloud or all-local | Hybrid with auto-fallback |
| Onboarding | Static walkthrough | Action-detection tutorial |
