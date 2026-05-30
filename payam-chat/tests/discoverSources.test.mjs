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

function makeDiscoverSources(apiResponse, catalogOverride) {
  return esmock('../src/tools/discoverSources.mjs', {
    '../src/anthropic.mjs': {
      MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
      callWithCachedSystem: async () => ({
        data: apiResponse,
        raw: JSON.stringify(apiResponse),
        usage: fakeUsage,
      }),
      sumUsage: (parts) => parts[0],
    },
    ...(catalogOverride ? { '../src/catalog.mjs': catalogOverride } : {}),
  });
}

describe('runDiscoverSources', () => {
  it('throws when topic is empty', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({});
    await assert.rejects(
      runDiscoverSources({ topic: '' }),
      /discover_sources requires a non-empty topic/,
    );
  });

  it('throws when topic is not a string', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({});
    await assert.rejects(
      runDiscoverSources({ topic: null }),
      /discover_sources requires a non-empty topic/,
    );
  });

  it('returns empty card list when no catalog matches', async () => {
    const { runDiscoverSources } = await makeDiscoverSources({}, {
      candidatesForTopic: () => [],
    });

    const result = await runDiscoverSources({ topic: 'xyznonexistenttopic123' });
    assert.equal(result.view.type, 'card_list');
    assert.equal(result.view.payload.cards.length, 0);
    assert.ok(result.view.payload.emptyReason);
    assert.equal(result.usage.model, 'none');
  });

  it('returns cards from API response filtering to valid catalog URLs', async () => {
    const candidates = [
      { name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', description: 'Apple news', category: 'Apple' },
      { name: 'MacRumors', feedURL: 'http://feeds.macrumors.com/MacRumors-Mac', description: 'Mac rumors', category: 'Apple' },
    ];

    const { runDiscoverSources } = await makeDiscoverSources(
      {
        cards: [
          {
            name: '9to5Mac',
            feedURL: 'https://9to5mac.com/feed',
            websiteURL: 'https://9to5mac.com',
            oneLine: 'Breaking Apple news.',
            sampleHeadlines: [],
            why: 'Great coverage.',
          },
          {
            name: 'FakeURL',
            feedURL: 'https://fake-not-in-catalog.com/feed',
            oneLine: 'Should be filtered.',
          },
        ],
      },
      { candidatesForTopic: () => candidates },
    );

    const result = await runDiscoverSources({ topic: 'apple', subscribedURLs: [] });
    assert.equal(result.view.type, 'card_list');
    assert.equal(result.view.payload.cards.length, 1);
    assert.equal(result.view.payload.cards[0].name, '9to5Mac');
    assert.equal(result.view.payload.cards[0].alreadySubscribed, false);
  });

  it('marks already subscribed feeds correctly (case-insensitive)', async () => {
    const candidates = [
      { name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', description: 'Apple news', category: 'Apple' },
    ];

    const { runDiscoverSources } = await makeDiscoverSources(
      {
        cards: [
          {
            name: '9to5Mac',
            feedURL: 'https://9to5mac.com/feed',
            oneLine: 'Apple news.',
          },
        ],
      },
      { candidatesForTopic: () => candidates },
    );

    const result = await runDiscoverSources({
      topic: 'apple',
      subscribedURLs: ['HTTPS://9TO5MAC.COM/FEED'],
    });
    assert.equal(result.view.payload.cards[0].alreadySubscribed, true);
  });

  it('handles cards with missing optional fields', async () => {
    const candidates = [
      { name: 'Test', feedURL: 'https://test.com/feed', description: 'Test', category: 'Test' },
    ];

    const { runDiscoverSources } = await makeDiscoverSources(
      {
        cards: [
          {
            name: 'Test',
            feedURL: 'https://test.com/feed',
            // no websiteURL, oneLine, sampleHeadlines, why
          },
        ],
      },
      { candidatesForTopic: () => candidates },
    );

    const result = await runDiscoverSources({ topic: 'test' });
    const card = result.view.payload.cards[0];
    assert.equal(card.websiteURL, null);
    assert.equal(card.oneLine, '');
    assert.deepEqual(card.sampleHeadlines, []);
    assert.equal(card.why, null);
  });

  it('handles non-array sampleHeadlines', async () => {
    const candidates = [
      { name: 'Test', feedURL: 'https://test.com/feed', description: 'Test', category: 'Test' },
    ];

    const { runDiscoverSources } = await makeDiscoverSources(
      {
        cards: [
          {
            name: 'Test',
            feedURL: 'https://test.com/feed',
            sampleHeadlines: 'not an array',
          },
        ],
      },
      { candidatesForTopic: () => candidates },
    );

    const result = await runDiscoverSources({ topic: 'test' });
    assert.deepEqual(result.view.payload.cards[0].sampleHeadlines, []);
  });
});
