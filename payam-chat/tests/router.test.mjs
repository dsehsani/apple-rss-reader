import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { classifyIntent } from '../src/router.mjs';

describe('classifyIntent', () => {
  it('returns unknown for empty messages array', async () => {
    const result = await classifyIntent([], null);
    assert.equal(result.intent, 'unknown');
    assert.equal(result.confidence, 0);
    assert.equal(result.usage.model, 'none');
    assert.equal(result.usage.inputTokens, 0);
    assert.equal(result.usage.outputTokens, 0);
  });

  it('returns unknown when no user messages exist', async () => {
    const messages = [
      { role: 'assistant', content: 'hello' },
      { role: 'system', content: 'be helpful' },
    ];
    const result = await classifyIntent(messages, null);
    assert.equal(result.intent, 'unknown');
    assert.equal(result.confidence, 0);
  });

  it('returns unknown with empty args for no user turns', async () => {
    const result = await classifyIntent([], null);
    assert.deepEqual(result.args, { raw: '' });
  });
});
