#!/usr/bin/env node
// Real-data tests — fetches actual RSS/Atom feeds and validates parsing.
// Catches encoding issues, malformed XML, broken dates, and edge cases
// that synthetic fixtures miss.
//
// Run: node --test tests/real-feeds.test.mjs
// Note: Requires internet access. Tests may be slow (network-bound).

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import Parser from "rss-parser";
import crypto from "node:crypto";

const parser = new Parser({
  timeout: 15_000,
  headers: {
    "User-Agent": "Payam/1.0 RSS Reader (https://payam.app)",
    Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
  },
  customFields: {
    item: [
      ["media:thumbnail", "mediaThumbnail", { keepArray: false }],
      ["media:content", "mediaContent", { keepArray: false }],
      ["enclosure"],
    ],
  },
});

// Velocity tier inference (from feed-worker.mjs)
function inferVelocityTier(itemsCount, daySpanSeconds) {
  const days = Math.max(1, daySpanSeconds / 86400);
  const perDay = itemsCount / days;
  if (perDay >= 50) return "breaking";
  if (perDay >= 10) return "news";
  if (perDay >= 1) return "article";
  if (perDay >= 0.15) return "essay";
  return "evergreen";
}

// Deterministic UUID (from feed-worker.mjs)
function deterministicUUID(feedId, link) {
  const input = `${feedId}|${link}`;
  const hash = crypto.createHash("md5").update(input).digest("hex");
  return [hash.substring(0, 8), hash.substring(8, 12), hash.substring(12, 16), hash.substring(16, 20), hash.substring(20, 32)].join("-");
}

// Image extraction (from feed-worker.mjs)
function extractImage(item) {
  if (item.mediaThumbnail?.$?.url) return item.mediaThumbnail.$.url;
  if (item.mediaContent?.$?.url && !item.mediaContent.$.type?.startsWith("audio/")) return item.mediaContent.$.url;
  if (item.enclosure?.type?.startsWith("image/")) return item.enclosure.url;
  const content = item["content:encoded"] || item.content || "";
  const imgMatch = content.match(/<img[^>]*src=["']([^"']+)["']/i);
  if (imgMatch) return imgMatch[1];
  return null;
}

function extractAudio(item) {
  if (item.enclosure?.type?.startsWith("audio/")) return item.enclosure.url;
  if (item.mediaContent?.$?.type?.startsWith("audio/")) return item.mediaContent.$.url;
  return null;
}

// Full item processing pipeline (mirrors feed-worker.mjs processFeed)
function processItems(feed, feedId, velocityTier) {
  return (feed.items || [])
    .filter((item) => item.title?.trim() && (item.link?.trim() || item.guid?.trim()))
    .map((item) => {
      const link = item.link?.trim() || item.guid?.trim();
      return {
        id: deterministicUUID(feedId, link),
        title: item.title.trim(),
        link,
        publishedAt: item.pubDate ? new Date(item.pubDate) : item.isoDate ? new Date(item.isoDate) : new Date(),
        excerpt: item.contentSnippet?.substring(0, 500)?.trim() || "",
        imageUrl: extractImage(item),
        audioUrl: extractAudio(item),
        author: item.creator || item["dc:creator"] || item.author || null,
      };
    });
}

// --- Test feeds: mix of RSS 2.0, Atom, podcasts, high-volume, edge cases ---
const TEST_FEEDS = [
  { name: "Hacker News",     url: "https://news.ycombinator.com/rss",             type: "rss",  expectedTier: "breaking" },
  { name: "Daring Fireball",  url: "https://daringfireball.net/feeds/main",        type: "atom", expectedTier: "article" },
  { name: "The Verge",        url: "https://www.theverge.com/rss/index.xml",       type: "rss",  expectedTier: "news" },
  { name: "Ars Technica",     url: "https://feeds.arstechnica.com/arstechnica/index", type: "rss", expectedTier: "news" },
  { name: "TechCrunch",       url: "https://techcrunch.com/feed/",                 type: "rss",  expectedTier: "news" },
  { name: "9to5Mac",          url: "https://9to5mac.com/feed",                     type: "rss",  expectedTier: "news" },
  { name: "MacStories",       url: "https://www.macstories.net/feed",              type: "rss",  expectedTier: "article" },
  { name: "NASA Breaking",    url: "https://www.nasa.gov/rss/dyn/breaking_news.rss", type: "rss", expectedTier: "article" },
  { name: "Swift Blog",       url: "https://www.swift.org/atom.xml",               type: "atom", expectedTier: "essay" },
];

// --- Performance tracking ---
const perfResults = [];

function timeMs(fn) {
  const start = performance.now();
  const result = fn();
  const elapsed = performance.now() - start;
  return { result, elapsed };
}

async function timeAsync(fn) {
  const start = performance.now();
  const result = await fn();
  const elapsed = performance.now() - start;
  return { result, elapsed };
}

// --- Tests ---

describe("Real Feed Parsing", { timeout: 60_000 }, () => {
  for (const feedInfo of TEST_FEEDS) {
    it(`parses ${feedInfo.name} (${feedInfo.type})`, async () => {
      // Fetch
      const { result: response, elapsed: fetchMs } = await timeAsync(() =>
        fetch(feedInfo.url, {
          headers: {
            "User-Agent": "Payam/1.0 RSS Reader (https://payam.app)",
            Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
          },
          signal: AbortSignal.timeout(15_000),
        })
      );

      assert.ok(response.ok, `Fetch failed: ${response.status} ${response.statusText}`);
      const xml = await response.text();
      assert.ok(xml.length > 0, "Response body should not be empty");

      // Parse
      const { result: feed, elapsed: parseMs } = await timeAsync(() => parser.parseString(xml));

      assert.ok(feed.title, `Feed should have title, got: ${feed.title}`);
      assert.ok(feed.items.length > 0, `Feed should have items, got: ${feed.items.length}`);

      // Process items through our pipeline
      const feedId = crypto.createHash("sha256").update(feedInfo.url).digest("hex").substring(0, 32);
      const { result: items, elapsed: processMs } = timeMs(() => processItems(feed, feedId, feedInfo.expectedTier));

      assert.ok(items.length > 0, `Should produce items, got: ${items.length}`);

      // Validate each item
      for (const item of items) {
        assert.ok(item.id, `Item should have id`);
        assert.ok(item.title.length > 0, `Item should have non-empty title`);
        assert.ok(item.link.startsWith("http"), `Item link should be a URL: ${item.link}`);
        assert.ok(item.publishedAt instanceof Date, `publishedAt should be a Date`);
        assert.ok(!isNaN(item.publishedAt.getTime()), `publishedAt should be a valid date, got: ${item.publishedAt} from item "${item.title}"`);
      }

      // Check for duplicates — some real feeds have items sharing the same link
      // (e.g., Daring Fireball uses the same link for different entries).
      // The worker handles this via ON CONFLICT DO NOTHING, but we should dedup here too.
      const seenLinks = new Set();
      const deduped = items.filter((i) => {
        if (seenLinks.has(i.link)) return false;
        seenLinks.add(i.link);
        return true;
      });
      if (deduped.length < items.length) {
        console.log(`  NOTE: ${feedInfo.name} has ${items.length - deduped.length} duplicate links (handled by ON CONFLICT)`);
      }

      // Velocity tier inference
      const dates = items.map((i) => i.publishedAt.getTime()).filter((d) => !isNaN(d));
      let inferredTier = "article";
      if (dates.length >= 2) {
        const span = (Math.max(...dates) - Math.min(...dates)) / 1000;
        inferredTier = inferVelocityTier(items.length, span);
      }

      // Record performance
      perfResults.push({
        feed: feedInfo.name,
        fetchMs: Math.round(fetchMs),
        parseMs: Math.round(parseMs * 100) / 100,
        processMs: Math.round(processMs * 100) / 100,
        xmlBytes: xml.length,
        rawItems: feed.items.length,
        validItems: items.length,
        withImage: items.filter((i) => i.imageUrl).length,
        withAudio: items.filter((i) => i.audioUrl).length,
        withAuthor: items.filter((i) => i.author).length,
        withExcerpt: items.filter((i) => i.excerpt.length > 0).length,
        inferredTier,
        expectedTier: feedInfo.expectedTier,
      });
    });
  }
});

// Print performance summary after all tests
process.on("exit", () => {
  if (perfResults.length === 0) return;

  console.log("\n╔══════════════════════════════════════════════════════════════════════════════════════════╗");
  console.log("║                           REAL FEED PERFORMANCE RESULTS                                ║");
  console.log("╠══════════════════════════════════════════════════════════════════════════════════════════╣");
  console.log("║ Feed               │ Fetch  │ Parse  │ Process │ XML KB │ Items │ Imgs │ Tier          ║");
  console.log("╟────────────────────┼────────┼────────┼─────────┼────────┼───────┼──────┼───────────────╢");

  for (const r of perfResults) {
    const name = r.feed.padEnd(19).substring(0, 19);
    const fetch = `${r.fetchMs}ms`.padStart(6);
    const parse = `${r.parseMs}ms`.padStart(6);
    const process = `${r.processMs}ms`.padStart(7);
    const size = `${Math.round(r.xmlBytes / 1024)}`.padStart(5);
    const items = `${r.validItems}/${r.rawItems}`.padStart(5);
    const imgs = `${r.withImage}`.padStart(4);
    const tier = `${r.inferredTier}`.padEnd(13);
    console.log(`║ ${name} │ ${fetch} │ ${parse} │ ${process} │ ${size}K │ ${items} │ ${imgs} │ ${tier} ║`);
  }

  console.log("╟────────────────────┴────────┴────────┴─────────┴────────┴───────┴──────┴───────────────╢");

  const avgFetch = Math.round(perfResults.reduce((s, r) => s + r.fetchMs, 0) / perfResults.length);
  const avgParse = Math.round(perfResults.reduce((s, r) => s + r.parseMs, 0) / perfResults.length * 100) / 100;
  const avgProcess = Math.round(perfResults.reduce((s, r) => s + r.processMs, 0) / perfResults.length * 100) / 100;
  const totalItems = perfResults.reduce((s, r) => s + r.validItems, 0);
  const totalImages = perfResults.reduce((s, r) => s + r.withImage, 0);

  console.log(`║ AVG: fetch=${avgFetch}ms  parse=${avgParse}ms  process=${avgProcess}ms                                  ║`);
  console.log(`║ TOTAL: ${totalItems} items parsed, ${totalImages} with images                                           ║`);

  // Data quality warnings
  const warnings = [];
  for (const r of perfResults) {
    if (r.validItems < r.rawItems * 0.5) warnings.push(`${r.feed}: ${r.rawItems - r.validItems} items dropped (missing title/link)`);
    if (r.withExcerpt < r.validItems * 0.3) warnings.push(`${r.feed}: only ${r.withExcerpt}/${r.validItems} items have excerpts`);
    if (r.parseMs > 100) warnings.push(`${r.feed}: slow parse (${r.parseMs}ms)`);
    if (r.inferredTier !== r.expectedTier) warnings.push(`${r.feed}: inferred ${r.inferredTier}, expected ${r.expectedTier}`);
  }

  if (warnings.length > 0) {
    console.log("╟──────────────────────────────────────────────────────────────────────────────────────────╢");
    console.log("║ WARNINGS:                                                                              ║");
    for (const w of warnings) {
      console.log(`║  - ${w.padEnd(84)}║`);
    }
  }

  console.log("╚══════════════════════════════════════════════════════════════════════════════════════════╝\n");
});
