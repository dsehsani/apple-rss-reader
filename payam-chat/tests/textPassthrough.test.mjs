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

describe('runTextPassthrough', () => {
  it('returns a text view with the model response', async () => {
    const { runTextPassthrough } = await esmock('../src/tools/textPassthrough.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async () => ({
          data: 'This is a response.',
          raw: 'This is a response.',
          usage: fakeUsage,
        }),
      },
    });

    const result = await runTextPassthrough({
      messages: [{ role: 'user', content: 'how do I add a feed?' }],
    });
    assert.equal(result.view.type, 'text');
    assert.equal(result.view.payload.content, 'This is a response.');
    assert.ok(result.usage);
  });

  it('appends article context to the last user message', async () => {
    let capturedMessages;
    const { runTextPassthrough } = await esmock('../src/tools/textPassthrough.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async (opts) => {
          capturedMessages = opts.messages;
          return {
            data: 'Summary here.',
            raw: 'Summary here.',
            usage: fakeUsage,
          };
        },
      },
    });

    await runTextPassthrough({
      messages: [{ role: 'user', content: 'summarize this' }],
      articleContext: { title: 'Test Article', feedName: 'TestFeed', content: 'Article body here.' },
    });

    const lastMsg = capturedMessages[capturedMessages.length - 1];
    assert.ok(lastMsg.content.includes('Test Article'));
    assert.ok(lastMsg.content.includes('TestFeed'));
    assert.ok(lastMsg.content.includes('Article body here.'));
  });

  it('filters out system messages', async () => {
    let capturedMessages;
    const { runTextPassthrough } = await esmock('../src/tools/textPassthrough.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async (opts) => {
          capturedMessages = opts.messages;
          return { data: 'ok', raw: 'ok', usage: fakeUsage };
        },
      },
    });

    await runTextPassthrough({
      messages: [
        { role: 'system', content: 'system prompt' },
        { role: 'user', content: 'hello' },
        { role: 'assistant', content: 'hi' },
      ],
    });

    assert.equal(capturedMessages.length, 2);
    assert.equal(capturedMessages[0].role, 'user');
    assert.equal(capturedMessages[1].role, 'assistant');
  });

  it('does not append article context when last message is not user', async () => {
    let capturedMessages;
    const { runTextPassthrough } = await esmock('../src/tools/textPassthrough.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async (opts) => {
          capturedMessages = opts.messages;
          return { data: 'ok', raw: 'ok', usage: fakeUsage };
        },
      },
    });

    await runTextPassthrough({
      messages: [
        { role: 'user', content: 'hello' },
        { role: 'assistant', content: 'hi there' },
      ],
      articleContext: { title: 'Test', feedName: 'Feed', content: 'Body' },
    });

    const lastMsg = capturedMessages[capturedMessages.length - 1];
    assert.ok(!lastMsg.content.includes('[Article context]'));
  });

  it('handles missing articleContext content gracefully', async () => {
    let capturedMessages;
    const { runTextPassthrough } = await esmock('../src/tools/textPassthrough.mjs', {
      '../src/anthropic.mjs': {
        MODELS: { HAIKU: 'claude-haiku-4-5-20251001', SONNET: 'claude-sonnet-4-6' },
        callWithCachedSystem: async (opts) => {
          capturedMessages = opts.messages;
          return { data: 'ok', raw: 'ok', usage: fakeUsage };
        },
      },
    });

    await runTextPassthrough({
      messages: [{ role: 'user', content: 'summarize' }],
      articleContext: { title: 'Test', feedName: 'Feed' },
    });

    const lastMsg = capturedMessages[capturedMessages.length - 1];
    assert.ok(lastMsg.content.includes('[Article context]'));
  });
});
