import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import esmock from 'esmock';

const fakeUsage = {
  model: 'claude-haiku-4-5-20251001',
  inputTokens: 10,
  cachedInputTokens: 5,
  cacheCreationInputTokens: 0,
  outputTokens: 20,
};

const webUsage = {
  model: 'claude-sonnet-4-6',
  inputTokens: 30,
  cachedInputTokens: 0,
  cacheCreationInputTokens: 0,
  outputTokens: 40,
};

/**
 * Build runDiscoverSources with mocked anthropic, catalog, and feed validator.
 *
 * @param {object} cfg
 * @param {Array}  [cfg.catalogCandidates] — what matchedCandidatesForTopic returns.
 * @param {object} [cfg.catalogResponse]   — Haiku rerank JSON ({ cards: [...] }).
 * @param {object} [cfg.webResponse]       — web-search JSON ({ candidates: [...] }).
 * @param {Function} [cfg.validate]        — (url) => validateFeed result. Default: all valid.
 * @param {boolean} [cfg.webThrows]        — make callWithWebSearch reject.
 */
function makeDiscoverSources(cfg = {}) {
  const {
    catalogCandidates = [],
    catalogResponse = { cards: [] },
    webResponse = { candidates: [] },
    validate,
    webThrows = false,
  } = cfg;

  const defaultValidate = (url) => ({
    ok: true,
    url,
    title: `Title for ${url}`,
    websiteURL: 'https://site.example',
    sampleHeadlines: ['Headline one', 'Headline two', 'Headline three'],
  });

  return esmock('../src/tools/discoverSources.mjs', {
    '../src/anthropic.mjs': {
      MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
      callWithCachedSystem: async () => ({
        data: catalogResponse,
        raw: JSON.stringify(catalogResponse),
        usage: fakeUsage,
      }),
      callWithWebSearch: async () => {
        if (webThrows) throw new Error('web search exploded');
        return { data: webResponse, raw: JSON.stringify(webResponse), usage: webUsage };
      },
      sumUsage: (parts) => ({ model: parts.map((p) => p.model).join('+'), parts: parts.length }),
    },
    '../src/catalog.mjs': {
      matchedCandidatesForTopic: () => catalogCandidates,
    },
    '../src/feedValidator.mjs': {
      validateFeeds: async (urls) => {
        const fn = validate || defaultValidate;
        return urls.map(fn).filter((r) => r.ok);
      },
    },
  });
}

const APPLE_CANDIDATES = [
  { name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', description: 'Apple news', category: 'Apple' },
  { name: 'MacRumors', feedURL: 'http://feeds.macrumors.com/MacRumors-Mac', description: 'Mac rumors', category: 'Apple' },
  { name: 'MacStories', feedURL: 'https://www.macstories.net/feed', description: 'Apps', category: 'Apple' },
];

describe('runDiscoverSources', () => {
  it('throws when topic is empty', async () => {
    const { runDiscoverSources } = await makeDiscoverSources();
    await assert.rejects(runDiscoverSources({ topic: '' }), /requires a non-empty topic/);
  });

  it('throws when topic is not a string', async () => {
    const { runDiscoverSources } = await makeDiscoverSources();
    await assert.rejects(runDiscoverSources({ topic: null }), /requires a non-empty topic/);
  });

  it('returns catalog cards without web search when catalog has >= 3 matches', async () => {
    let webCalled = false;
    const mod = await esmock('../src/tools/discoverSources.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'h', SONNET: 's' },
        callWithCachedSystem: async () => ({
          data: {
            cards: APPLE_CANDIDATES.map((c) => ({ name: c.name, feedURL: c.feedURL, oneLine: 'x' })),
          },
          usage: fakeUsage,
        }),
        callWithWebSearch: async () => { webCalled = true; return { data: { candidates: [] }, usage: webUsage }; },
        sumUsage: (parts) => parts[0],
      },
      '../src/catalog.mjs': { matchedCandidatesForTopic: () => APPLE_CANDIDATES },
      '../src/feedValidator.mjs': { validateFeeds: async () => [] },
    });

    const result = await mod.runDiscoverSources({ topic: 'apple', subscribedURLs: [] });
    assert.equal(result.view.type, 'card_list');
    assert.equal(result.view.payload.cards.length, 3);
    assert.equal(webCalled, false, 'should not call web search when catalog suffices');
  });

  it('falls back to AI web discovery when catalog has no match', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: [],
      webResponse: {
        candidates: [
          { name: 'ESPN FC', feedURL: 'https://espn.com/soccer.xml', oneLine: 'Soccer news', why: 'global coverage' },
          { name: 'BBC Sport Football', feedURL: 'https://feeds.bbci.co.uk/sport/football/rss.xml', oneLine: 'BBC football' },
        ],
      },
    });

    const result = await runDiscoverSources({ topic: 'soccer', subscribedURLs: [] });
    assert.equal(result.view.payload.cards.length, 2);
    assert.equal(result.view.payload.cards[0].name, 'ESPN FC');
    // sample headlines come from the verifier (capped at 2).
    assert.equal(result.view.payload.cards[0].sampleHeadlines.length, 2);
  });

  it('filters Reddit feeds from AI-discovered candidates', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: [],
      webResponse: {
        candidates: [
          { name: 'r/soccer', feedURL: 'https://reddit.com/r/soccer/.rss', oneLine: 'Community' },
          { name: 'ESPN FC', feedURL: 'https://espn.com/soccer.xml', oneLine: 'Soccer news' },
        ],
      },
    });

    const result = await runDiscoverSources({ topic: 'soccer' });
    const urls = result.view.payload.cards.map((c) => c.feedURL);
    assert.ok(!urls.some((u) => /reddit\.com/i.test(u)), 'no Reddit feeds in results');
    assert.equal(result.view.payload.cards.length, 1);
    assert.equal(result.view.payload.cards[0].name, 'ESPN FC');
  });

  it('drops AI-discovered feeds that fail validation', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: [],
      webResponse: {
        candidates: [
          { name: 'Live Feed', feedURL: 'https://good.example/feed', oneLine: 'works' },
          { name: 'Dead Feed', feedURL: 'https://dead.example/feed', oneLine: '404' },
        ],
      },
      validate: (url) =>
        url.includes('dead')
          ? { ok: false, url, title: null, websiteURL: null, sampleHeadlines: [] }
          : { ok: true, url, title: 'Live', websiteURL: 'https://good.example', sampleHeadlines: ['h1'] },
    });

    const result = await runDiscoverSources({ topic: 'soccer' });
    assert.equal(result.view.payload.cards.length, 1);
    assert.equal(result.view.payload.cards[0].name, 'Live Feed');
  });

  it('supplements a thin catalog (< 3) with verified AI feeds', async () => {
    const thin = [APPLE_CANDIDATES[0]];
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: thin,
      catalogResponse: { cards: [{ name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', oneLine: 'Apple' }] },
      webResponse: {
        candidates: [
          { name: 'Extra A', feedURL: 'https://a.example/feed', oneLine: 'a' },
          { name: 'Extra B', feedURL: 'https://b.example/feed', oneLine: 'b' },
        ],
      },
    });

    const result = await runDiscoverSources({ topic: 'apple' });
    const names = result.view.payload.cards.map((c) => c.name);
    assert.ok(names.includes('9to5Mac'));
    assert.ok(names.includes('Extra A'));
    assert.ok(result.view.payload.cards.length <= 5);
  });

  it('dedupes AI feeds already present in catalog cards', async () => {
    const thin = [APPLE_CANDIDATES[0]];
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: thin,
      catalogResponse: { cards: [{ name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', oneLine: 'Apple' }] },
      webResponse: {
        candidates: [
          { name: 'dup', feedURL: 'HTTPS://9TO5MAC.COM/FEED', oneLine: 'dup' },
          { name: 'New', feedURL: 'https://new.example/feed', oneLine: 'new' },
        ],
      },
    });

    const result = await runDiscoverSources({ topic: 'apple' });
    const urls = result.view.payload.cards.map((c) => c.feedURL.toLowerCase());
    assert.equal(new Set(urls).size, urls.length, 'no duplicate URLs');
    assert.equal(urls.filter((u) => u === 'https://9to5mac.com/feed').length, 1);
  });

  it('returns an empty card list with reason when nothing is found', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: [],
      webResponse: { candidates: [] },
    });
    const result = await runDiscoverSources({ topic: 'zzztopic' });
    assert.equal(result.view.payload.cards.length, 0);
    assert.match(result.view.payload.emptyReason, /zzztopic/);
  });

  it('is resilient when web discovery throws', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: [],
      webThrows: true,
    });
    const result = await runDiscoverSources({ topic: 'soccer' });
    assert.equal(result.view.payload.cards.length, 0);
    assert.ok(result.view.payload.emptyReason);
  });

  it('marks already-subscribed feeds (case-insensitive)', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: APPLE_CANDIDATES,
      catalogResponse: {
        cards: APPLE_CANDIDATES.map((c) => ({ name: c.name, feedURL: c.feedURL, oneLine: 'x' })),
      },
    });
    const result = await runDiscoverSources({
      topic: 'apple',
      subscribedURLs: ['HTTPS://9TO5MAC.COM/FEED'],
    });
    const card = result.view.payload.cards.find((c) => c.feedURL === 'https://9to5mac.com/feed');
    assert.equal(card.alreadySubscribed, true);
  });

  it('filters Haiku cards whose URL is not in the candidate set', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({
      catalogCandidates: APPLE_CANDIDATES,
      catalogResponse: {
        cards: [
          { name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', oneLine: 'real' },
          { name: 'Fake', feedURL: 'https://hallucinated.example/feed', oneLine: 'nope' },
          { name: 'MacRumors', feedURL: 'http://feeds.macrumors.com/MacRumors-Mac', oneLine: 'real' },
          { name: 'MacStories', feedURL: 'https://www.macstories.net/feed', oneLine: 'real' },
        ],
      },
    });
    const result = await runDiscoverSources({ topic: 'apple' });
    const urls = result.view.payload.cards.map((c) => c.feedURL);
    assert.ok(!urls.includes('https://hallucinated.example/feed'));
    assert.equal(result.view.payload.cards.length, 3);
  });
});
