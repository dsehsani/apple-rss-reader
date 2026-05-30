import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { sumUsage, MODELS } from '../src/anthropic.mjs';

describe('MODELS', () => {
  it('exports HAIKU model ID', () => {
    assert.ok(typeof MODELS.HAIKU === 'string');
    assert.ok(MODELS.HAIKU.includes('haiku'));
  });

  it('exports SONNET model ID', () => {
    assert.ok(typeof MODELS.SONNET === 'string');
    assert.ok(MODELS.SONNET.includes('sonnet'));
  });
});

describe('sumUsage', () => {
  it('sums two usage objects', () => {
    const a = { model: 'haiku', inputTokens: 100, cachedInputTokens: 50, cacheCreationInputTokens: 10, outputTokens: 20 };
    const b = { model: 'sonnet', inputTokens: 200, cachedInputTokens: 100, cacheCreationInputTokens: 5, outputTokens: 40 };
    const result = sumUsage([a, b]);

    assert.equal(result.inputTokens, 300);
    assert.equal(result.cachedInputTokens, 150);
    assert.equal(result.cacheCreationInputTokens, 15);
    assert.equal(result.outputTokens, 60);
    assert.equal(result.model, 'haiku+sonnet');
  });

  it('handles missing fields gracefully', () => {
    const a = { model: 'haiku', inputTokens: 100 };
    const b = { model: 'sonnet', outputTokens: 50 };
    const result = sumUsage([a, b]);

    assert.equal(result.inputTokens, 100);
    assert.equal(result.cachedInputTokens, 0);
    assert.equal(result.outputTokens, 50);
  });

  it('handles single usage object', () => {
    const a = { model: 'haiku', inputTokens: 100, cachedInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 25 };
    const result = sumUsage([a]);

    assert.equal(result.inputTokens, 100);
    assert.equal(result.outputTokens, 25);
    assert.equal(result.model, 'haiku');
  });

  it('handles three usage objects', () => {
    const parts = [
      { model: 'a', inputTokens: 10, cachedInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 5 },
      { model: 'b', inputTokens: 20, cachedInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 10 },
      { model: 'c', inputTokens: 30, cachedInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 15 },
    ];
    const result = sumUsage(parts);
    assert.equal(result.inputTokens, 60);
    assert.equal(result.outputTokens, 30);
    assert.equal(result.model, 'a+b+c');
  });
});
