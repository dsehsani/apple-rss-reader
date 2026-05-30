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

function makeRouter(apiResponse) {
  return esmock('../src/router.mjs', {
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

describe('classifyIntent', () => {
  it('returns unknown when no user messages', async () => {
    const { classifyIntent } = await makeRouter({});
    const result = await classifyIntent([{ role: 'assistant', content: 'hello' }], null);
    assert.equal(result.intent, 'unknown');
    assert.equal(result.confidence, 0);
  });

  it('classifies a valid intent from API response', async () => {
    const { classifyIntent } = await makeRouter({
      intent: 'source_discovery',
      args: { topic: 'AI' },
      confidence: 0.95,
    });
    const result = await classifyIntent(
      [{ role: 'user', content: 'find feeds about AI' }],
      null,
    );
    assert.equal(result.intent, 'source_discovery');
    assert.deepEqual(result.args, { topic: 'AI' });
    assert.equal(result.confidence, 0.95);
    assert.equal(result.usage.model, 'claude-haiku-4-5-20251001');
  });

  it('falls back to unknown for invalid intent', async () => {
    const { classifyIntent } = await makeRouter({
      intent: 'totally_fake_intent',
      args: { foo: 'bar' },
      confidence: 0.9,
    });
    const result = await classifyIntent(
      [{ role: 'user', content: 'do something weird' }],
      null,
    );
    assert.equal(result.intent, 'unknown');
  });

  it('defaults args to {} when missing', async () => {
    const { classifyIntent } = await makeRouter({
      intent: 'explain',
      args: null,
      confidence: 0.8,
    });
    const result = await classifyIntent(
      [{ role: 'user', content: 'how do I add a feed?' }],
      null,
    );
    assert.deepEqual(result.args, {});
  });

  it('defaults args to {} when args is not an object', async () => {
    const { classifyIntent } = await makeRouter({
      intent: 'explain',
      args: 'string-not-object',
      confidence: 0.8,
    });
    const result = await classifyIntent(
      [{ role: 'user', content: 'how?' }],
      null,
    );
    assert.deepEqual(result.args, {});
  });

  it('defaults confidence to 0.5 when not a number', async () => {
    const { classifyIntent } = await makeRouter({
      intent: 'explain',
      args: {},
      confidence: 'high',
    });
    const result = await classifyIntent(
      [{ role: 'user', content: 'hello' }],
      null,
    );
    assert.equal(result.confidence, 0.5);
  });

  it('includes articleContext in the user body when provided', async () => {
    let capturedMessages;
    const { classifyIntent } = await esmock('../src/router.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async (opts) => {
          capturedMessages = opts.messages;
          return {
            data: { intent: 'summarize', args: {}, confidence: 0.9 },
            raw: '{}',
            usage: fakeUsage,
          };
        },
      },
    });

    await classifyIntent(
      [{ role: 'user', content: 'summarize this' }],
      { title: 'Test Article', feedName: 'TestFeed' },
    );
    assert.ok(capturedMessages[0].content.includes('Test Article'));
    assert.ok(capturedMessages[0].content.includes('TestFeed'));
  });
});
