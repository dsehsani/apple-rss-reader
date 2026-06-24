// check-catalog-health.mjs — standalone health check for the Discover catalog.
//
// The Discover tab is powered by a static catalog of RSS URLs mirrored in two
// files: Payam/Models/RSSCatalog.swift (canonical, iOS) and
// payam-chat/src/catalog.mjs (server mirror). When a publisher moves or kills a
// feed there is no signal — the dead source just sits in Discovery. This script
// fetches every catalog feed and classifies it so breakage can be caught
// proactively (run monthly from .github/workflows/feed-health.yml, or locally via
// `npm run check:catalog`).
//
// Classification:
//   DEAD        — 404/410/451, or a 2xx body that does not parse as a feed (e.g.
//                 a rebranded site now serving HTML). Confident + actionable.
//   STALE       — parses fine, but the newest item is older than STALE_DAYS.
//   UNVERIFIED  — network/TLS error, timeout, or bot-block (403/429/5xx). These
//                 are usually client- or CI-environment artifacts (datacenter IP
//                 blocks, Node's stricter TLS chain handling) rather than a dead
//                 feed, so they are reported but do NOT fail the run on their own.
//   OK          — parses fine with a recent item.
//
// We fetch with Node's global fetch + a desktop browser User-Agent (to match how
// the iOS app / a browser sees these feeds), then parse the body with rss-parser
// (already a payam-polling dependency). The catalog is read from the JS mirror —
// the machine-readable copy of the hand-kept Swift catalog. Exit code is non-zero
// only when an actionable problem (DEAD or STALE) is found.

import Parser from 'rss-parser';
import { CATALOG } from '../../payam-chat/src/catalog.mjs';

const TIMEOUT_MS = 15_000;
const CONCURRENCY = 8;
const STALE_DAYS = 90;
const STALE_MS = STALE_DAYS * 24 * 60 * 60 * 1000;

// Desktop Safari UA — several publishers (Reddit, Cloudflare-fronted sites)
// return 403/timeouts to a bare Node/library UA but serve the feed to a browser.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/16 Safari/605.1.15';
const ACCEPT =
  'application/rss+xml, application/atom+xml, application/json, text/xml, */*';

const parser = new Parser();

/** Flatten the catalog to a deduped list of feeds (keyed by URL). */
function catalogFeeds() {
  const seen = new Map();
  for (const cat of CATALOG) {
    for (const feed of cat.feeds ?? []) {
      const key = feed.feedURL.toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, { category: cat.category, name: feed.name, feedURL: feed.feedURL });
      }
    }
  }
  return [...seen.values()];
}

/** Newest item timestamp in ms, or null if no datable item exists. */
function newestItemMs(items) {
  let newest = null;
  for (const it of items ?? []) {
    const raw = it.isoDate ?? it.pubDate ?? null;
    if (!raw) continue;
    const ms = Date.parse(raw);
    if (Number.isFinite(ms) && (newest === null || ms > newest)) newest = ms;
  }
  return newest;
}

/** Classify a single feed. Returns { ...feed, status, detail }. */
async function checkFeed(feed, nowMs) {
  const ctrl = new AbortController();
  const tm = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetch(feed.feedURL, {
      headers: { 'User-Agent': USER_AGENT, 'Accept': ACCEPT },
      redirect: 'follow',
      signal: ctrl.signal,
    });
  } catch (err) {
    // DNS failure, TLS chain error, connection refused, abort/timeout — all
    // ambiguous from CI. Report, but don't treat as a confident death.
    return { ...feed, status: 'UNVERIFIED', detail: `fetch failed: ${shortErr(err)}` };
  } finally {
    clearTimeout(tm);
  }

  if (res.status === 404 || res.status === 410 || res.status === 451) {
    return { ...feed, status: 'DEAD', detail: `HTTP ${res.status}` };
  }
  if (!res.ok) {
    // 403/429 (bot-block) and 5xx (transient) are usually environment artifacts.
    return { ...feed, status: 'UNVERIFIED', detail: `HTTP ${res.status}` };
  }

  let body;
  try {
    body = await res.text();
  } catch (err) {
    return { ...feed, status: 'UNVERIFIED', detail: `read failed: ${shortErr(err)}` };
  }

  let parsed;
  try {
    parsed = await parser.parseString(body);
  } catch (err) {
    // 2xx but the body isn't a feed → site likely rebranded/moved. Actionable.
    return { ...feed, status: 'DEAD', detail: `not a feed: ${shortErr(err)}` };
  }

  const items = parsed.items ?? [];
  if (items.length === 0) {
    return { ...feed, status: 'DEAD', detail: 'parsed but contains no items' };
  }

  const newest = newestItemMs(items);
  if (newest === null) {
    // Items present but undatable — can't assess staleness; treat as OK.
    return { ...feed, status: 'OK', detail: `${items.length} items, no dates` };
  }
  const ageDays = Math.floor((nowMs - newest) / (24 * 60 * 60 * 1000));
  if (nowMs - newest > STALE_MS) {
    return { ...feed, status: 'STALE', detail: `newest item ${ageDays}d old` };
  }
  return { ...feed, status: 'OK', detail: `newest item ${ageDays}d old` };
}

function shortErr(err) {
  const msg = String(err?.cause?.message ?? err?.message ?? err);
  return msg.replace(/\s+/g, ' ').slice(0, 100);
}

/** Run checks with bounded concurrency, preserving input order. */
async function runAll(feeds, nowMs) {
  const results = new Array(feeds.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= feeds.length) return;
      results[i] = await checkFeed(feeds[i], nowMs);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, feeds.length) }, worker));
  return results;
}

function renderMarkdown(results) {
  const dead = results.filter((r) => r.status === 'DEAD');
  const stale = results.filter((r) => r.status === 'STALE');
  const unverified = results.filter((r) => r.status === 'UNVERIFIED');
  const ok = results.filter((r) => r.status === 'OK');

  const lines = [];
  lines.push('## Discovery catalog feed health');
  lines.push('');
  lines.push(
    `**${ok.length} OK · ${stale.length} stale (>${STALE_DAYS}d) · ${dead.length} dead · ` +
    `${unverified.length} unverified** — ${results.length} feeds checked.`,
  );
  lines.push('');

  const section = (title, rows) => {
    if (rows.length === 0) return;
    lines.push(`### ${title} (${rows.length})`);
    lines.push('');
    lines.push('| Category | Feed | URL | Detail |');
    lines.push('| --- | --- | --- | --- |');
    for (const r of rows) {
      lines.push(`| ${r.category} | ${r.name} | ${r.feedURL} | ${r.detail} |`);
    }
    lines.push('');
  };

  section('🔴 Dead', dead);
  section('🟡 Stale', stale);
  section('⚪ Unverified (could not confirm — likely transient or CI/network)', unverified);
  return lines.join('\n');
}

async function main() {
  const nowMs = Date.now();
  const feeds = catalogFeeds();
  const results = await runAll(feeds, nowMs);

  const markdown = renderMarkdown(results);
  console.log(markdown);

  // Write to the GitHub Actions job summary when running in CI.
  if (process.env.GITHUB_STEP_SUMMARY) {
    const { appendFile } = await import('node:fs/promises');
    await appendFile(process.env.GITHUB_STEP_SUMMARY, markdown + '\n');
  }

  // Only DEAD/STALE are actionable enough to fail the run / open an issue.
  const actionable = results.filter((r) => r.status === 'DEAD' || r.status === 'STALE');
  process.exitCode = actionable.length > 0 ? 1 : 0;
}

main().catch((err) => {
  console.error('check-catalog-health failed:', err);
  process.exitCode = 2;
});
