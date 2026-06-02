// Feed content verifier.
//
// AI-discovered feed URLs are NOT trusted — a model can suggest a plausible-looking
// URL that 404s, redirects to HTML, or points at a dead/empty feed. Before we ever
// surface an AI-discovered feed to the user, `validateFeed` fetches it and confirms
// it is a real RSS/Atom/RDF document that contains at least one item/entry. It also
// pulls out the feed title, a few sample headlines, and the site URL so the card can
// prove the feed has real content.
//
// Uses Node 20's global `fetch` (no extra dependency). `fetch` is referenced via a
// module-level binding so tests can swap in a mock via esmock.

const fetchImpl = (...args) => fetch(...args);

const FEED_USER_AGENT = 'PayamFeedValidator/1.0 (+https://payam.app)';
const MAX_BYTES = 512 * 1024; // cap how much of a feed body we read/parse.

/** Decode the handful of XML entities that show up in feed titles. */
function decodeEntities(s) {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;|&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
    .trim();
}

/** Pull the text of the first `<tag>...</tag>` (namespace-tolerant) from `xml`. */
function firstTag(xml, tag) {
  const re = new RegExp(`<(?:[\\w-]+:)?${tag}\\b[^>]*>([\\s\\S]*?)</(?:[\\w-]+:)?${tag}>`, 'i');
  const m = re.exec(xml);
  return m ? decodeEntities(m[1]) : null;
}

/**
 * Extract up to `limit` item/entry titles from a feed body. Works for RSS `<item>`
 * and Atom `<entry>` blocks.
 */
function extractHeadlines(xml, limit = 3) {
  const headlines = [];
  const blockRe = /<(item|entry)\b[^>]*>([\s\S]*?)<\/\1>/gi;
  let m;
  while ((m = blockRe.exec(xml)) && headlines.length < limit) {
    const title = firstTag(m[2], 'title');
    if (title) headlines.push(title);
  }
  return headlines;
}

/** Best-effort website URL: the feed's non-self <link>, else the feed URL's origin. */
function deriveWebsiteURL(xml, feedURL) {
  // Atom: <link rel="alternate" href="..."/> or a bare <link href="...">.
  const atom = /<link\b[^>]*\bhref=["']([^"']+)["'][^>]*>/gi;
  let m;
  while ((m = atom.exec(xml))) {
    const tag = m[0];
    if (/rel=["']self["']/i.test(tag)) continue;
    if (/rel=["'](?!alternate)/i.test(tag)) continue;
    if (m[1] && !m[1].endsWith('.xml') && !m[1].endsWith('.rss')) return m[1];
  }
  // RSS: <link>https://site</link> inside the channel (first one, not an item link).
  const rss = firstTag(xml, 'link');
  if (rss && /^https?:\/\//i.test(rss)) return rss;
  try {
    return new URL(feedURL).origin;
  } catch {
    return null;
  }
}

/** Does this body look like an RSS/Atom/RDF feed at all? */
function looksLikeFeed(body) {
  return /<rss[\s>]/i.test(body) || /<feed[\s>]/i.test(body) || /<rdf:RDF[\s>]/i.test(body);
}

/**
 * Fetch a feed URL and verify it's a working feed with content.
 *
 * @param {string} url
 * @param {object} [opts]
 * @param {number} [opts.timeoutMs=4000]
 * @returns {Promise<{ok: boolean, url: string, title: string|null, websiteURL: string|null, sampleHeadlines: string[], reason?: string}>}
 */
export async function validateFeed(url, { timeoutMs = 4000 } = {}) {
  const fail = (reason) => ({ ok: false, url, title: null, websiteURL: null, sampleHeadlines: [], reason });

  if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) {
    return fail('not an http(s) url');
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, {
      method: 'GET',
      redirect: 'follow',
      signal: controller.signal,
      headers: { 'User-Agent': FEED_USER_AGENT, Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*' },
    });

    if (!res.ok) return fail(`http ${res.status}`);

    const body = (await res.text()).slice(0, MAX_BYTES);
    if (!looksLikeFeed(body)) return fail('body is not a feed');

    const headlines = extractHeadlines(body);
    if (headlines.length === 0) return fail('feed has no items');

    return {
      ok: true,
      url,
      title: firstTag(body, 'title'),
      websiteURL: deriveWebsiteURL(body, url),
      sampleHeadlines: headlines,
    };
  } catch (e) {
    return fail(e?.name === 'AbortError' ? 'timeout' : e?.message || 'fetch failed');
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Validate many feed URLs in parallel, returning only the ones that pass (in input
 * order). Never throws — a rejected/failed validation just drops that URL.
 *
 * @param {string[]} urls
 * @param {object} [opts] forwarded to `validateFeed`.
 * @returns {Promise<Array<{ok: true, url: string, title: string|null, websiteURL: string|null, sampleHeadlines: string[]}>>}
 */
export async function validateFeeds(urls, opts = {}) {
  const settled = await Promise.allSettled(urls.map((u) => validateFeed(u, opts)));
  return settled
    .filter((s) => s.status === 'fulfilled' && s.value.ok)
    .map((s) => s.value);
}
