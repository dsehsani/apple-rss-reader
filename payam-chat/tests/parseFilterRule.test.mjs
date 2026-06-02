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

function makeParseFilterRule(apiResponse) {
  return esmock('../src/tools/parseFilterRule.mjs', {
    '../src/anthropic.mjs': {
      MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
      callWithCachedSystem: async () => ({
        data: apiResponse,
        raw: JSON.stringify(apiResponse),
        usage: fakeUsage,
      }),
    },
  });
}

describe('runParseFilterRule', () => {
  it('returns a valid rule_card view from API response', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Hide opinion pieces',
      predicate: {
        keywords: [],
        phrases: [],
        sourceFeedURLs: [],
        contentKinds: ['opinion'],
      },
      scope: 'global',
      rationale: 'Suppresses opinion articles across all feeds.',
    });

    const result = await runParseFilterRule({ text: 'stop showing me opinion pieces' });
    assert.equal(result.view.type, 'rule_card');
    assert.equal(result.view.payload.displayText, 'Hide opinion pieces');
    assert.deepEqual(result.view.payload.predicate.contentKinds, ['opinion']);
    assert.equal(result.view.payload.scope, 'global');
    assert.equal(result.view.payload.sourceText, 'stop showing me opinion pieces');
    assert.ok(result.usage);
  });

  it('throws when text is empty', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({});
    await assert.rejects(
      runParseFilterRule({ text: '' }),
      /parse_filter_rule requires non-empty text/,
    );
  });

  it('throws when text is not a string', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({});
    await assert.rejects(
      runParseFilterRule({ text: null }),
      /parse_filter_rule requires non-empty text/,
    );
  });

  it('sanitizes predicate — filters invalid contentKinds', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {
        keywords: ['test'],
        phrases: [],
        sourceFeedURLs: [],
        contentKinds: ['opinion', 'INVALID_KIND', 'podcast'],
      },
      scope: 'global',
      rationale: 'Test rationale',
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.deepEqual(result.view.payload.predicate.contentKinds, ['opinion', 'podcast']);
  });

  it('sanitizes predicate — filters non-string keywords', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {
        keywords: ['valid', 123, null, 'also-valid'],
        phrases: [42, 'good'],
        sourceFeedURLs: [true, 'https://example.com'],
        contentKinds: [],
      },
      scope: 'global',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'filter something' });
    assert.deepEqual(result.view.payload.predicate.keywords, ['valid', 'also-valid']);
    assert.deepEqual(result.view.payload.predicate.phrases, ['good']);
    assert.deepEqual(result.view.payload.predicate.sourceFeedURLs, ['https://example.com']);
  });

  it('handles missing predicate fields gracefully', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {},
      scope: 'global',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.deepEqual(result.view.payload.predicate.keywords, []);
    assert.deepEqual(result.view.payload.predicate.phrases, []);
    assert.deepEqual(result.view.payload.predicate.sourceFeedURLs, []);
    assert.deepEqual(result.view.payload.predicate.contentKinds, []);
  });

  it('handles missing predicate entirely', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      scope: 'global',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.deepEqual(result.view.payload.predicate.keywords, []);
  });

  it('defaults scope to global when invalid', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {},
      scope: 'invalid_scope',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.equal(result.view.payload.scope, 'global');
  });

  it('accepts valid folder scope', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {},
      scope: 'folder:Apple',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide stuff in apple folder' });
    assert.equal(result.view.payload.scope, 'folder:Apple');
  });

  it('accepts valid feed scope', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {},
      scope: 'feed:https://example.com/rss',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide from this feed' });
    assert.equal(result.view.payload.scope, 'feed:https://example.com/rss');
  });

  it('truncates displayText to 120 chars', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'A'.repeat(200),
      predicate: {},
      scope: 'global',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.equal(result.view.payload.displayText.length, 120);
  });

  it('truncates rationale to 200 chars', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      displayText: 'Test',
      predicate: {},
      scope: 'global',
      rationale: 'B'.repeat(300),
    });

    const result = await runParseFilterRule({ text: 'hide stuff' });
    assert.equal(result.view.payload.rationale.length, 200);
  });

  it('defaults displayText when missing', async () => {
    const { runParseFilterRule } = await makeParseFilterRule({
      predicate: {},
      scope: 'global',
      rationale: '',
    });

    const result = await runParseFilterRule({ text: 'hide' });
    assert.equal(result.view.payload.displayText, 'New filter');
  });
});
