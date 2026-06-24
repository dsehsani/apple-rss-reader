#!/usr/bin/env node
// test-discover-feeds.mjs
// Validates every RSS/Atom feed listed in Payam/Models/RSSCatalog.swift.
//
// For each feed:
//   1. Fetches the URL (follows redirects, 10 s timeout).
//   2. Confirms it responds with valid RSS/Atom XML.
//   3. Scans the first 3 items for images via media:content, media:thumbnail,
//      enclosure, <img> in description HTML, or og:image.
//
// Usage:
//   node scripts/test-discover-feeds.mjs

import https from 'node:https';
import http  from 'node:http';
import { URL } from 'node:url';

// ─── Config ────────────────────────────────────────────────────────────────

const TIMEOUT_MS   = 12_000;
const MAX_REDIRECTS = 5;
const CONCURRENCY  = 10;
const ITEMS_TO_CHECK = 3;
const MAX_BODY_BYTES = 512 * 1024; // stop buffering after 512 KB — enough for image detection

// ─── Feed list (deduplicated from RSSCatalog.swift) ────────────────────────

const FEEDS = [
  // Tech
  { name: 'Hacker News',          category: 'Tech',        url: 'https://news.ycombinator.com/rss' },
  { name: 'The Verge',            category: 'Tech',        url: 'https://www.theverge.com/rss/index.xml' },
  { name: 'Ars Technica',         category: 'Tech',        url: 'http://feeds.arstechnica.com/arstechnica/index' },
  { name: 'TechCrunch',           category: 'Tech',        url: 'http://feeds.feedburner.com/TechCrunch' },
  { name: 'Gizmodo',              category: 'Tech',        url: 'https://gizmodo.com/rss' },
  { name: 'Stratechery',          category: 'Tech',        url: 'http://stratechery.com/feed/' },
  { name: 'The Next Web',         category: 'Tech',        url: 'https://thenextweb.com/feed/' },
  { name: 'Engadget',             category: 'Tech',        url: 'https://www.engadget.com/rss.xml' },
  { name: 'Lifehacker',           category: 'Tech',        url: 'https://lifehacker.com/rss' },
  { name: 'Slashdot',             category: 'Tech',        url: 'http://rss.slashdot.org/Slashdot/slashdotMain' },
  // Apple
  { name: '9to5Mac',              category: 'Apple',       url: 'https://9to5mac.com/feed' },
  { name: 'Apple Newsroom',       category: 'Apple',       url: 'https://www.apple.com/newsroom/rss-feed.rss' },
  { name: 'AppleInsider',         category: 'Apple',       url: 'https://appleinsider.com/rss/news/' },
  { name: 'Cult of Mac',          category: 'Apple',       url: 'https://www.cultofmac.com/feed' },
  { name: 'Daring Fireball',      category: 'Apple',       url: 'https://daringfireball.net/feeds/main' },
  { name: 'MacStories',           category: 'Apple',       url: 'https://www.macstories.net/feed' },
  { name: 'MacRumors',            category: 'Apple',       url: 'http://feeds.macrumors.com/MacRumors-Mac' },
  // Programming
  { name: 'Stack Overflow Blog',  category: 'Programming', url: 'https://stackoverflow.blog/feed/' },
  { name: 'GitHub Blog',          category: 'Programming', url: 'https://github.blog/feed/' },
  { name: 'Joel on Software',     category: 'Programming', url: 'https://www.joelonsoftware.com/feed/' },
  { name: 'Martin Fowler',        category: 'Programming', url: 'https://martinfowler.com/feed.atom' },
  { name: 'Netflix TechBlog',     category: 'Programming', url: 'https://netflixtechblog.com/feed' },
  { name: 'Coding Horror',        category: 'Programming', url: 'https://feeds.feedburner.com/codinghorror' },
  { name: 'InfoQ',                category: 'Programming', url: 'https://feed.infoq.com' },
  { name: 'Spotify Engineering',  category: 'Programming', url: 'https://labs.spotify.com/feed/' },
  { name: 'Overreacted',          category: 'Programming', url: 'https://overreacted.io/rss.xml' },
  { name: 'Facebook Engineering', category: 'Programming', url: 'https://engineering.fb.com/feed/' },
  // Science
  { name: 'BBC Science & Env',    category: 'Science',     url: 'http://feeds.bbci.co.uk/news/science_and_environment/rss.xml' },
  { name: 'Scientific American',  category: 'Science',     url: 'http://rss.sciam.com/sciam/60secsciencepodcast' },
  { name: 'Gizmodo Science',      category: 'Science',     url: 'https://gizmodo.com/tag/science/rss' },
  { name: 'Hidden Brain',         category: 'Science',     url: 'https://feeds.npr.org/510308/podcast.xml' },
  { name: 'FlowingData',          category: 'Science',     url: 'https://flowingdata.com/feed' },
  { name: 'Invisibilia',          category: 'Science',     url: 'https://feeds.npr.org/510307/podcast.xml' },
  // News
  { name: 'BBC News – World',     category: 'News',        url: 'http://feeds.bbci.co.uk/news/world/rss.xml' },
  { name: 'NYT World News',       category: 'News',        url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml' },
  { name: 'Google News',          category: 'News',        url: 'https://news.google.com/rss' },
  { name: 'Washington Post',      category: 'News',        url: 'http://feeds.washingtonpost.com/rss/world' },
  { name: 'CNBC International',   category: 'News',        url: 'https://www.cnbc.com/id/100727362/device/rss/rss.html' },
  { name: 'r/worldnews',          category: 'News',        url: 'https://www.reddit.com/r/worldnews/.rss' },
  { name: 'NDTV World News',      category: 'News',        url: 'http://feeds.feedburner.com/ndtvnews-world-news' },
  // Gaming
  { name: 'Kotaku',               category: 'Gaming',      url: 'https://kotaku.com/rss' },
  { name: 'IGN',                  category: 'Gaming',      url: 'http://feeds.ign.com/ign/all' },
  { name: 'Eurogamer',            category: 'Gaming',      url: 'https://www.eurogamer.net/?format=rss' },
  { name: 'GameSpot',             category: 'Gaming',      url: 'https://www.gamespot.com/feeds/mashup/' },
  { name: 'Indie Games Plus',     category: 'Gaming',      url: 'https://indiegamesplus.com/feed' },
  { name: 'Gamasutra',            category: 'Gaming',      url: 'http://feeds.feedburner.com/GamasutraNews' },
  { name: 'Escapist Magazine',    category: 'Gaming',      url: 'https://www.escapistmagazine.com/v2/feed/' },
  // Music
  { name: 'Pitchfork',            category: 'Music',       url: 'http://pitchfork.com/rss/news' },
  { name: 'Billboard',            category: 'Music',       url: 'https://www.billboard.com/articles/rss.xml' },
  { name: 'Consequence of Sound', category: 'Music',       url: 'http://consequenceofsound.net/feed' },
  { name: 'Song Exploder',        category: 'Music',       url: 'http://songexploder.net/feed' },
  { name: 'Music Biz Worldwide',  category: 'Music',       url: 'https://www.musicbusinessworldwide.com/feed/' },
  { name: 'Your EDM',             category: 'Music',       url: 'https://www.youredm.com/feed' },
  // Business
  { name: 'Forbes Business',      category: 'Business',    url: 'https://www.forbes.com/business/feed/' },
  { name: 'Fortune',              category: 'Business',    url: 'https://fortune.com/feed' },
  { name: 'Inc.com',              category: 'Business',    url: 'https://www.inc.com/rss/' },
  { name: 'Economic Times',       category: 'Business',    url: 'https://economictimes.indiatimes.com/rssfeedsdefault.cms' },
  { name: 'Seeking Alpha',        category: 'Business',    url: 'https://seekingalpha.com/market_currents.xml' },
  { name: 'Duct Tape Marketing',  category: 'Business',    url: 'https://ducttape.libsyn.com/rss' },
  // Startups
  { name: 'HN: Front Page',       category: 'Startups',    url: 'https://hnrss.org/frontpage' },
  { name: 'AVC',                  category: 'Startups',    url: 'https://avc.com/feed/' },
  { name: 'Both Sides of Table',  category: 'Startups',    url: 'https://bothsidesofthetable.com/feed' },
  { name: 'Entrepreneur',         category: 'Startups',    url: 'http://feeds.feedburner.com/entrepreneur/latest' },
  { name: 'Forbes Entrepreneurs', category: 'Startups',    url: 'https://www.forbes.com/entrepreneurs/feed/' },
  { name: 'Feld Thoughts',        category: 'Startups',    url: 'https://feld.com/feed' },
  // Space
  { name: 'NASA Breaking News',   category: 'Space',       url: 'https://www.nasa.gov/rss/dyn/breaking_news.rss' },
  { name: 'Space.com',            category: 'Space',       url: 'https://www.space.com/feeds/all' },
  { name: 'The Guardian: Space',  category: 'Space',       url: 'https://www.theguardian.com/science/space/rss' },
  { name: 'Sky & Telescope',      category: 'Space',       url: 'https://www.skyandtelescope.com/feed/' },
  { name: 'r/space',              category: 'Space',       url: 'https://www.reddit.com/r/space/.rss?format=xml' },
  { name: 'New Scientist: Space', category: 'Space',       url: 'https://www.newscientist.com/subject/space/feed/' },
  // iOS Dev
  { name: 'Swift by Sundell',     category: 'iOS Dev',     url: 'https://www.swiftbysundell.com/feed.rss' },
  { name: 'Apple Developer News', category: 'iOS Dev',     url: 'https://developer.apple.com/news/rss/news.rss' },
  { name: 'Augmented Code',       category: 'iOS Dev',     url: 'https://augmentedcode.io/feed/' },
  { name: 'Ole Begemann',         category: 'iOS Dev',     url: 'https://oleb.net/blog/atom.xml' },
  { name: 'More Than Just Code',  category: 'iOS Dev',     url: 'https://feeds.fireside.fm/mtjc/rss' },
  // Books
  { name: 'Book Riot',            category: 'Books',       url: 'https://bookriot.com/feed/' },
  { name: 'Kirkus Reviews',       category: 'Books',       url: 'https://www.kirkusreviews.com/feeds/rss/' },
  { name: 'r/books',              category: 'Books',       url: 'https://reddit.com/r/books/.rss' },
  { name: 'A Year of Reading',    category: 'Books',       url: 'https://ayearofreadingtheworld.com/feed/' },
];

// ─── HTTP fetch (redirect-following, timeout, body cap) ────────────────────

function fetchUrl(urlStr, redirectsLeft = MAX_REDIRECTS) {
  return new Promise((resolve, reject) => {
    if (redirectsLeft < 0) return reject(new Error('Too many redirects'));

    let parsed;
    try { parsed = new URL(urlStr); }
    catch { return reject(new Error(`Invalid URL: ${urlStr}`)); }

    const lib = parsed.protocol === 'https:' ? https : http;
    const req = lib.request(
      {
        hostname: parsed.hostname,
        port:     parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
        path:     parsed.pathname + parsed.search,
        method:   'GET',
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; PayamFeedTester/1.0; +https://github.com/payam)',
          'Accept':     'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
        },
        timeout: TIMEOUT_MS,
      },
      (res) => {
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
          res.resume();
          const next = new URL(res.headers.location, urlStr).toString();
          return fetchUrl(next, redirectsLeft - 1).then(resolve).catch(reject);
        }

        const chunks = [];
        let received = 0;
        let capped = false;
        let settled = false;

        const finish = () => {
          if (settled) return;
          settled = true;
          resolve({
            status:      res.statusCode ?? 0,
            contentType: res.headers['content-type'] ?? '',
            body:        Buffer.concat(chunks).toString('utf-8'),
          });
        };

        res.on('data', (chunk) => {
          if (capped) return;
          received += chunk.length;
          chunks.push(chunk);
          if (received >= MAX_BODY_BYTES) {
            capped = true;
            finish();       // resolve first with partial body so feed isn't falsely dead
            res.destroy();  // stop downloading; 'close' fires but settled=true guards finish
          }
        });

        res.on('end', finish);
        res.on('error', (err) => {
          if (settled) return;
          if (capped) finish();
          else reject(err);
        });
      }
    );

    req.on('timeout', () => req.destroy(new Error('Timed out')));
    req.on('error',   reject);
    req.end();
  });
}

// ─── Feed validation ───────────────────────────────────────────────────────

function isValidFeed(status, contentType, body) {
  if (status !== 200) return false;
  const xmlContentType = /xml|rss|atom/i.test(contentType);
  // Some servers return text/plain or text/html for valid feeds — check the body too
  const looksLikeXml = /<(rss|feed|channel|rdf:RDF)/i.test(body.slice(0, 2000));
  return xmlContentType || looksLikeXml;
}

// ─── Image detection ───────────────────────────────────────────────────────

// Pull the raw text of the first N <item> or <entry> blocks.
function extractItemBlocks(xml, n) {
  const blocks = [];
  const re = /<(item|entry)[\s>]([\s\S]*?)<\/\1>/gi;
  let m;
  while ((m = re.exec(xml)) !== null && blocks.length < n) {
    blocks.push(m[0]);
  }
  return blocks;
}

function blockHasImage(block) {
  // media:content or media:thumbnail with a url= attribute
  if (/<media:(content|thumbnail)[^>]+url=/i.test(block)) return true;
  // <enclosure type="image/..."> (RSS podcasts / photo feeds)
  if (/<enclosure[^>]+type="image\//i.test(block)) return true;
  // Atom: <link rel="enclosure" type="image/..."/>
  if (/<link[^>]+rel=["']enclosure["'][^>]+type=["']image\//i.test(block)) return true;
  // <img src="..."> embedded in description / content HTML (very common)
  if (/<img[\s][^>]*src=/i.test(block)) return true;
  // og:image anywhere in the item (rare but possible in some custom feeds)
  if (/og:image/i.test(block)) return true;
  return false;
}

function feedHasImages(xml) {
  const blocks = extractItemBlocks(xml, ITEMS_TO_CHECK);
  return blocks.length > 0 && blocks.some(blockHasImage);
}

// ─── Concurrency pool ──────────────────────────────────────────────────────

async function runConcurrent(tasks, limit) {
  const results = new Array(tasks.length);
  let next = 0;
  async function worker() {
    while (next < tasks.length) {
      const i = next++;
      results[i] = await tasks[i]();
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, tasks.length) }, worker));
  return results;
}

// ─── Table helpers ─────────────────────────────────────────────────────────

const C = { NAME: 24, CAT: 12, URL: 50, STATUS: 10, IMG: 6 };
const ROW_WIDTH = C.NAME + C.CAT + C.URL + C.STATUS + C.IMG + 5;

function pad(s, w)      { return String(s ?? '').padEnd(w); }
function trunc(s, w)    { s = String(s ?? ''); return s.length > w ? s.slice(0, w - 1) + '…' : s; }
function hr(ch = '─')   { return ch.repeat(ROW_WIDTH); }
function header() {
  return `${pad('Feed', C.NAME)} ${pad('Category', C.CAT)} ${pad('URL', C.URL)} ${pad('Status', C.STATUS)} Img`;
}
function row(r) {
  const statusStr = r.working
    ? '✓ OK'
    : (r.httpStatus ? `✗ ${r.httpStatus}` : `✗ ERR`);
  const imgStr = r.working ? (r.images ? 'yes' : 'no') : '—';
  return `${pad(trunc(r.name, C.NAME), C.NAME)} ${pad(r.category, C.CAT)} ${pad(trunc(r.url, C.URL), C.URL)} ${pad(statusStr, C.STATUS)} ${imgStr}`;
}

// ─── Main ──────────────────────────────────────────────────────────────────

async function main() {

console.log(`\nPayam Discover Feed Tester`);
console.log(`Testing ${FEEDS.length} feeds  concurrency=${CONCURRENCY}  timeout=${TIMEOUT_MS / 1000}s\n`);

const tasks = FEEDS.map((feed) => async () => {
  process.stdout.write('.');
  try {
    const { status, contentType, body } = await fetchUrl(feed.url);
    const working = isValidFeed(status, contentType, body);
    const images  = working ? feedHasImages(body) : false;
    return { ...feed, httpStatus: status, working, images, error: null };
  } catch (err) {
    return { ...feed, httpStatus: null, working: false, images: false, error: err.message };
  }
});

const results = await runConcurrent(tasks, CONCURRENCY);
console.log('\n');

// ─── Print table, grouped by category ──────────────────────────────────────

// Preserve original category order
const categoryOrder = [...new Set(FEEDS.map(f => f.category))];
const byCategory = Object.fromEntries(categoryOrder.map(c => [c, []]));
for (const r of results) byCategory[r.category].push(r);

console.log(hr());
console.log(header());
console.log(hr());

for (const cat of categoryOrder) {
  for (const r of byCategory[cat]) {
    console.log(row(r));
  }
  console.log(hr('·'));
}

// ─── Summary ───────────────────────────────────────────────────────────────

const dead    = results.filter(r => !r.working);
const noImg   = results.filter(r => r.working && !r.images);
const working = results.filter(r => r.working);

console.log(`\nResult: ${working.length} working  ${dead.length} dead  ${noImg.length} no-image\n`);

if (dead.length > 0) {
  console.log(`Dead feeds — consider removing from RSSCatalog.swift (${dead.length}):`);
  for (const r of dead) {
    const reason = r.error ?? `HTTP ${r.httpStatus}`;
    console.log(`  ✗ [${r.category}] ${r.name}`);
    console.log(`      ${r.url}`);
    console.log(`      reason: ${reason}`);
  }
  console.log();
}

if (noImg.length > 0) {
  console.log(`Working feeds with no images in first ${ITEMS_TO_CHECK} items (${noImg.length}):`);
  for (const r of noImg) {
    console.log(`  · [${r.category}] ${r.name}`);
    console.log(`      ${r.url}`);
  }
  console.log();
}

} // end main

main().catch(console.error);
