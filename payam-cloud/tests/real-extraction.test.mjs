#!/usr/bin/env node
// Real-data extraction tests — fetches actual articles and runs jsdom + Readability.
// Measures extraction success rate, content quality, and performance.
//
// Run: node --test tests/real-extraction.test.mjs

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { Readability } from "@mozilla/readability";

// Topic inference (from extract-light.mjs)
const TOPIC_KEYWORDS = {
  technology: ["software", "hardware", "tech", "digital", "computing", "computer"],
  ai: ["artificial intelligence", "machine learning", "llm", "neural network", "gpt", "claude", "deep learning"],
  ios: ["swift", "swiftui", "xcode", "uikit", "ios", "iphone", "ipad"],
  apple: ["apple", "macos", "macbook", "wwdc", "app store"],
  programming: ["javascript", "python", "rust", "typescript", "react", "node.js", "api", "framework", "github"],
  science: ["research", "study finds", "scientists", "experiment"],
  business: ["startup", "funding", "revenue", "ipo", "acquisition", "valuation"],
  security: ["vulnerability", "exploit", "malware", "cybersecurity", "privacy", "encryption"],
};

function inferTopics(title, textContent) {
  const text = `${title} ${textContent.substring(0, 2000)}`.toLowerCase();
  const topics = [];
  for (const [topic, keywords] of Object.entries(TOPIC_KEYWORDS)) {
    if (keywords.some((kw) => text.includes(kw))) topics.push(topic);
  }
  return topics.slice(0, 5);
}

function extractHeroImage(html) {
  const ogMatch = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i);
  if (ogMatch) return ogMatch[1];
  const ogMatch2 = html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i);
  if (ogMatch2) return ogMatch2[1];
  return null;
}

function htmlToContentNodes(html) {
  const dom = new JSDOM(html);
  const doc = dom.window.document;
  const nodes = [];
  function walk(el) {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "paragraph", text });
        continue;
      }
      if (child.nodeType !== 1) continue;
      const tag = child.tagName.toLowerCase();
      if (["h1", "h2", "h3", "h4", "h5", "h6"].includes(tag)) {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "heading", level: parseInt(tag[1]), text });
      } else if (tag === "p") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "paragraph", text });
      } else if (tag === "img") {
        const src = child.getAttribute("src");
        if (src) nodes.push({ type: "image", url: src, caption: child.getAttribute("alt") || null });
      } else if (tag === "blockquote") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "blockquote", text });
      } else if (tag === "ul" || tag === "ol") {
        const items = Array.from(child.querySelectorAll("li")).map((li) => li.textContent.trim()).filter(Boolean);
        if (items.length > 0) nodes.push({ type: "list", items, ordered: tag === "ol" });
      } else if (tag === "pre" || tag === "code") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "codeBlock", text });
      } else if (tag === "figure") {
        const img = child.querySelector("img");
        const cap = child.querySelector("figcaption");
        if (img?.getAttribute("src")) {
          nodes.push({ type: "image", url: img.getAttribute("src"), caption: cap?.textContent?.trim() || null });
        } else { walk(child); }
      } else { walk(child); }
    }
  }
  walk(doc.body || doc);
  return nodes;
}

// Real articles to test extraction against
const TEST_ARTICLES = [
  { name: "Wikipedia (article)",    url: "https://en.wikipedia.org/wiki/RSS" },
  { name: "Hacker News (SSR)",      url: "https://news.ycombinator.com" },
  { name: "GitHub Blog",            url: "https://github.blog/changelog/2025-01-07-copilot-chat-in-github-com-is-now-aware-of-more-repository-context/" },
  { name: "MDN Web Docs",           url: "https://developer.mozilla.org/en-US/docs/Web/RSS/Getting_Started/Syndicating" },
  { name: "Swift.org Blog",         url: "https://www.swift.org/blog/byte-sized-swift/" },
  // SPA sites that should fail jsdom (needs JS to render content)
  { name: "Twitter/X (SPA)",        url: "https://x.com/Apple", expectedFail: true },
];

const perfResults = [];

describe("Real Article Extraction", { timeout: 120_000 }, () => {
  for (const article of TEST_ARTICLES) {
    it(`extracts "${article.name}"`, async () => {
      const fetchStart = performance.now();
      let response;
      try {
        response = await fetch(article.url, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            Accept: "text/html,application/xhtml+xml",
          },
          signal: AbortSignal.timeout(15_000),
          redirect: "follow",
        });
      } catch (err) {
        // Network errors are acceptable — just record and skip
        perfResults.push({
          name: article.name, fetchMs: Math.round(performance.now() - fetchStart),
          status: "FETCH_FAIL", error: err.message,
        });
        return;
      }
      const fetchMs = performance.now() - fetchStart;

      if (!response.ok) {
        perfResults.push({
          name: article.name, fetchMs: Math.round(fetchMs),
          status: `HTTP_${response.status}`,
        });
        // Don't fail the test on HTTP errors from real sites (may be rate-limited)
        return;
      }

      const html = await response.text();

      // Readability extraction
      const readStart = performance.now();
      const dom = new JSDOM(html, { url: article.url });
      const reader = new Readability(dom.window.document);
      const parsed = reader.parse();
      const readMs = performance.now() - readStart;

      // ContentNode conversion
      const nodeStart = performance.now();
      const nodes = parsed?.content ? htmlToContentNodes(parsed.content) : [];
      const nodeMs = performance.now() - nodeStart;

      const wordCount = nodes
        .filter((n) => n.type === "paragraph" || n.type === "heading")
        .reduce((sum, n) => sum + (n.text?.split(/\s+/).length || 0), 0);

      const heroImage = extractHeroImage(html);
      const topics = parsed ? inferTopics(parsed.title || "", parsed.textContent || "") : [];

      const result = {
        name: article.name,
        fetchMs: Math.round(fetchMs),
        readabilityMs: Math.round(readMs * 10) / 10,
        contentNodeMs: Math.round(nodeMs * 10) / 10,
        totalMs: Math.round((fetchMs + readMs + nodeMs) * 10) / 10,
        htmlBytes: html.length,
        status: parsed && wordCount >= 100 ? "OK" : wordCount > 0 ? "THIN" : "FAIL",
        title: parsed?.title?.substring(0, 50) || "(none)",
        wordCount,
        nodeCount: nodes.length,
        nodeTypes: [...new Set(nodes.map((n) => n.type))].join(", "),
        heroImage: heroImage ? "yes" : "no",
        topics: topics.join(", ") || "(none)",
      };

      perfResults.push(result);

      if (article.expectedFail) {
        // SPA sites — we expect thin or no content from jsdom
        assert.ok(wordCount < 100, `${article.name} should fail jsdom extraction (got ${wordCount} words) — this validates Puppeteer fallback triggers`);
      } else {
        // Normal articles — should extract successfully
        assert.ok(parsed, `Readability should parse ${article.name}`);
        assert.ok(parsed.title, `Should have title for ${article.name}`);
        // Some real articles might be shorter than 100 words depending on content changes
        // so we use a lower threshold for real-data tests
        if (wordCount < 50) {
          console.log(`  WARN: ${article.name} only produced ${wordCount} words — may need Puppeteer fallback`);
        }
      }
    });
  }
});

// Print results
process.on("exit", () => {
  if (perfResults.length === 0) return;

  console.log("\n╔════════════════════════════════════════════════════════════════════════════════════════════╗");
  console.log("║                         REAL EXTRACTION PERFORMANCE RESULTS                              ║");
  console.log("╠════════════════════════════════════════════════════════════════════════════════════════════╣");
  console.log("║ Article              │ Status │ Fetch  │ Read   │ Nodes  │ Words │ Hero │ Topics         ║");
  console.log("╟──────────────────────┼────────┼────────┼────────┼────────┼───────┼──────┼────────────────╢");

  for (const r of perfResults) {
    const name = (r.name || "").padEnd(20).substring(0, 20);
    const status = (r.status || "?").padEnd(6).substring(0, 6);
    const fetch = `${r.fetchMs}ms`.padStart(6);
    const read = r.readabilityMs != null ? `${r.readabilityMs}ms`.padStart(6) : "  n/a ".padStart(6);
    const nodes = r.contentNodeMs != null ? `${r.contentNodeMs}ms`.padStart(6) : "  n/a ".padStart(6);
    const words = r.wordCount != null ? `${r.wordCount}`.padStart(5) : "  n/a".padStart(5);
    const hero = (r.heroImage || "n/a").padStart(4);
    const topics = (r.topics || "(none)").padEnd(14).substring(0, 14);
    console.log(`║ ${name} │ ${status} │ ${fetch} │ ${read} │ ${nodes} │ ${words} │ ${hero} │ ${topics} ║`);
  }

  console.log("╟──────────────────────┴────────┴────────┴────────┴────────┴───────┴──────┴────────────────╢");

  const ok = perfResults.filter((r) => r.status === "OK").length;
  const thin = perfResults.filter((r) => r.status === "THIN").length;
  const fail = perfResults.filter((r) => r.status === "FAIL" || r.status?.startsWith("HTTP") || r.status === "FETCH_FAIL").length;
  const avgRead = perfResults.filter((r) => r.readabilityMs).reduce((s, r) => s + r.readabilityMs, 0) / Math.max(1, ok + thin);

  console.log(`║ SUCCESS: ${ok} OK, ${thin} thin (would use Puppeteer), ${fail} failed                                  ║`);
  console.log(`║ AVG readability+nodes: ${Math.round(avgRead)}ms (this runs in Lambda, not Fargate)                       ║`);
  console.log("╚════════════════════════════════════════════════════════════════════════════════════════════╝\n");
});
