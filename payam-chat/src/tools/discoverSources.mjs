import { MODELS, callWithCachedSystem, callWithWebSearch, sumUsage } from '../anthropic.mjs';
import { DISCOVER_SOURCES_SYSTEM } from '../prompts/discover-sources.mjs';
import { DISCOVER_WEB_SYSTEM } from '../prompts/discover-web.mjs';
import { matchedCandidatesForTopic } from '../catalog.mjs';
import { validateFeeds } from '../feedValidator.mjs';

const MAX_CARDS = 5;
const MIN_CATALOG_CARDS = 3; // below this, supplement with AI web discovery.

// Latency budget for the AI discovery path. Web search dominates wall-clock, so we
// cap the number of searches; validation is fast and parallel but we still bound the
// fan-out and per-feed timeout so a few slow hosts can't stall the whole response.
const WEB_SEARCH_MAX_USES = 2;
// Validation is parallel, so a higher cap adds ~no wall-clock — it just improves yield
// (more candidates checked → more survivors). Wall-clock is bounded by the single
// slowest fetch, i.e. FEED_TIMEOUT_MS, regardless of how many we validate.
const MAX_VALIDATE = 12;
const FEED_TIMEOUT_MS = 3500;

/**
 * discover_sources tool — returns a card_list view payload.
 *
 * Strategy (catalog-first, AI-fallback, verify-the-AI-results):
 *   1. Match the topic against Payam's curated catalog. Catalog feeds are trusted.
 *   2. If the catalog yields >= 3 relevant cards, return them (fast, cheap).
 *   3. Otherwise use Claude + web search to discover real feeds for ANY topic, then
 *      FETCH each candidate to confirm it's a live feed with content before showing
 *      it (no dead/hallucinated URLs reach the user).
 *   4. Merge catalog + verified AI cards, dedupe, cap at 5.
 *
 * @param {object} args
 * @param {string} args.topic — short topic phrase.
 * @param {string[]} [args.subscribedURLs] — feed URLs the user already follows.
 * @returns {{view: object, usage: object}}
 */
export async function runDiscoverSources({ topic, subscribedURLs = [] }) {
  if (!topic || typeof topic !== 'string') {
    throw new Error('discover_sources requires a non-empty topic');
  }

  const subscribedLower = new Set(subscribedURLs.map((u) => u.toLowerCase()));
  const usageParts = [];

  // --- 1. Catalog pass (trusted, no validation) ---
  const candidates = matchedCandidatesForTopic(topic, { limit: 8 });
  let catalogCards = [];
  if (candidates.length > 0) {
    const rerank = await rerankCatalog({ topic, candidates, subscribedURLs });
    catalogCards = rerank.cards;
    usageParts.push(rerank.usage);
  }

  // --- 2. Enough strong catalog matches? Done. ---
  if (catalogCards.length >= MIN_CATALOG_CARDS) {
    return finalize({ topic, cards: catalogCards, subscribedLower, usageParts });
  }

  // --- 3. AI web discovery + content verification for the gap ---
  const exclude = new Set(catalogCards.map((c) => c.feedURL.toLowerCase()));
  const ai = await discoverViaWeb({ topic, exclude });
  usageParts.push(ai.usage);

  const cards = [...catalogCards, ...ai.cards];
  return finalize({ topic, cards, subscribedLower, usageParts });
}

/**
 * Re-rank curated catalog candidates with Haiku and shape them into cards.
 * Output URLs are constrained to the candidate set (no hallucinated URLs).
 */
async function rerankCatalog({ topic, candidates, subscribedURLs }) {
  const userMsg = [
    `Topic: "${topic}"`,
    '',
    'Candidates:',
    ...candidates.map(
      (c) =>
        `- {name: ${JSON.stringify(c.name)}, feedURL: ${JSON.stringify(c.feedURL)}, description: ${JSON.stringify(c.description)}, category: ${JSON.stringify(c.category)}}`,
    ),
    '',
    `Already subscribed: ${JSON.stringify(subscribedURLs)}`,
  ].join('\n');

  const { data, usage } = await callWithCachedSystem({
    model: MODELS.HAIKU,
    system: DISCOVER_SOURCES_SYSTEM,
    messages: [{ role: 'user', content: userMsg }],
    maxTokens: 800,
    responseJSON: true,
  });

  const validURLs = new Set(candidates.map((c) => c.feedURL));
  const cards = (data.cards || [])
    .filter((c) => c && typeof c.feedURL === 'string' && validURLs.has(c.feedURL))
    .map((c) => ({
      name: c.name,
      feedURL: c.feedURL,
      websiteURL: c.websiteURL ?? null,
      oneLine: c.oneLine ?? '',
      sampleHeadlines: Array.isArray(c.sampleHeadlines) ? c.sampleHeadlines : [],
      why: c.why ?? null,
    }));

  return { cards, usage };
}

/**
 * Discover feeds for an arbitrary topic via web search, then verify each candidate
 * by fetching it. Only feeds that resolve to a live RSS/Atom document with at least
 * one item survive. Verified metadata (real title + sample headlines) is preferred
 * over the model's claims so the card reflects the feed's actual content.
 */
async function discoverViaWeb({ topic, exclude = new Set() }) {
  let proposed = [];
  let usage = { model: 'none', inputTokens: 0, cachedInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 0 };

  try {
    // Haiku is ~2x faster than Sonnet at processing the web-search result payload and
    // finds equally good feed URLs for this task, so it owns the latency-sensitive path.
    const { data, usage: u } = await callWithWebSearch({
      model: MODELS.HAIKU,
      system: DISCOVER_WEB_SYSTEM,
      messages: [{ role: 'user', content: `Topic: "${topic}"` }],
      maxTokens: 1200,
      maxUses: WEB_SEARCH_MAX_USES,
      responseJSON: true,
    });
    usage = u;
    proposed = Array.isArray(data.candidates) ? data.candidates : [];
  } catch (e) {
    // Discovery is best-effort — a search/parse failure just yields no AI cards.
    console.error('Web discovery failed:', e.message);
    return { cards: [], usage };
  }

  // Dedupe + drop Reddit (rate-limits RSS with 429) + anything already covered.
  const seen = new Set(exclude);
  const unique = [];
  for (const c of proposed) {
    const url = typeof c?.feedURL === 'string' ? c.feedURL.trim() : '';
    if (!url) continue;
    if (/reddit\.com/i.test(url)) continue; // Reddit returns 429 on RSS; skip it
    const key = url.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push({ ...c, feedURL: url });
    if (unique.length >= MAX_VALIDATE) break;
  }

  // Verify each candidate actually returns feed content. Drop the dead ones.
  const verified = await validateFeeds(unique.map((c) => c.feedURL), { timeoutMs: FEED_TIMEOUT_MS });
  const verifiedByURL = new Map(verified.map((v) => [v.url.toLowerCase(), v]));

  // Build cards, then float image-rich feeds to the top — they render better in the app.
  const rawCards = unique
    .filter((c) => verifiedByURL.has(c.feedURL.toLowerCase()))
    .map((c) => {
      const v = verifiedByURL.get(c.feedURL.toLowerCase());
      return {
        name: c.name || v.title || c.feedURL,
        feedURL: c.feedURL,
        websiteURL: c.websiteURL || v.websiteURL || null,
        oneLine: c.oneLine ?? '',
        sampleHeadlines: v.sampleHeadlines.slice(0, 2),
        why: c.why ?? null,
        hasImages: v.hasImages ?? false,
      };
    });

  rawCards.sort((a, b) => (b.hasImages ? 1 : 0) - (a.hasImages ? 1 : 0));
  const cards = rawCards.map(({ hasImages: _, ...card }) => card);

  return { cards, usage };
}

/**
 * Apply subscription flags, cap the card count, and wrap in the card_list envelope.
 * Surfaces a helpful empty reason when nothing usable was found.
 */
function finalize({ topic, cards, subscribedLower, usageParts }) {
  const capped = cards.slice(0, MAX_CARDS).map((c) => ({
    ...c,
    alreadySubscribed: subscribedLower.has(c.feedURL.toLowerCase()),
  }));

  const payload = { topic, cards: capped };
  if (capped.length === 0) {
    payload.emptyReason = `Couldn't find working feeds for "${topic}" right now — try rephrasing or a broader topic.`;
  }

  const usage = usageParts.length > 0
    ? sumUsage(usageParts)
    : { model: 'none', inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 };

  return { view: { type: 'card_list', payload }, usage };
}
