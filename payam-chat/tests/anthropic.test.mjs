import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import esmock from 'esmock';

describe('anthropic', () => {
  describe('sumUsage', () => {
    it('sums usage across multiple parts', async () => {
      const { sumUsage } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
      });

      const result = sumUsage([
        { model: 'haiku', inputTokens: 10, cachedInputTokens: 5, cacheCreationInputTokens: 2, outputTokens: 20 },
        { model: 'sonnet', inputTokens: 15, cachedInputTokens: 3, cacheCreationInputTokens: 1, outputTokens: 30 },
      ]);
      assert.equal(result.model, 'haiku+sonnet');
      assert.equal(result.inputTokens, 25);
      assert.equal(result.cachedInputTokens, 8);
      assert.equal(result.cacheCreationInputTokens, 3);
      assert.equal(result.outputTokens, 50);
    });

    it('handles missing fields in parts', async () => {
      const { sumUsage } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
      });

      const result = sumUsage([
        { model: 'haiku' },
        { model: 'sonnet', inputTokens: 10 },
      ]);
      assert.equal(result.inputTokens, 10);
      assert.equal(result.cachedInputTokens, 0);
      assert.equal(result.outputTokens, 0);
    });
  });

  describe('callWithCachedSystem', () => {
    it('returns parsed JSON when responseJSON is true', async () => {
      const { callWithCachedSystem, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
        '@anthropic-ai/sdk': {
          default: class {
            constructor() {}
            get messages() {
              return {
                create: async () => ({
                  content: [{ type: 'text', text: '"intent":"explain","args":{},"confidence":0.9}' }],
                  usage: { input_tokens: 10, cache_read_input_tokens: 5, cache_creation_input_tokens: 0, output_tokens: 20 },
                }),
              };
            }
          },
        },
      });

      const result = await callWithCachedSystem({
        model: MODELS.HAIKU,
        system: 'test system prompt',
        messages: [{ role: 'user', content: 'hello' }],
        maxTokens: 200,
        responseJSON: true,
      });
      assert.deepEqual(result.data, { intent: 'explain', args: {}, confidence: 0.9 });
      assert.equal(result.usage.model, MODELS.HAIKU);
      assert.equal(result.usage.inputTokens, 10);
    });

    it('returns raw text when responseJSON is false', async () => {
      const { callWithCachedSystem, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
        '@anthropic-ai/sdk': {
          default: class {
            constructor() {}
            get messages() {
              return {
                create: async () => ({
                  content: [{ type: 'text', text: 'Hello there!' }],
                  usage: { input_tokens: 5, output_tokens: 10 },
                }),
              };
            }
          },
        },
      });

      const result = await callWithCachedSystem({
        model: MODELS.HAIKU,
        system: 'test system prompt',
        messages: [{ role: 'user', content: 'hello' }],
        maxTokens: 200,
        responseJSON: false,
      });
      assert.equal(result.data, 'Hello there!');
      assert.equal(result.raw, 'Hello there!');
    });

    it('throws on invalid JSON response', async () => {
      const { callWithCachedSystem, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
        '@anthropic-ai/sdk': {
          default: class {
            constructor() {}
            get messages() {
              return {
                create: async () => ({
                  content: [{ type: 'text', text: 'not valid json at all' }],
                  usage: { input_tokens: 5, output_tokens: 10 },
                }),
              };
            }
          },
        },
      });

      await assert.rejects(
        callWithCachedSystem({
          model: MODELS.HAIKU,
          system: 'test',
          messages: [{ role: 'user', content: 'hello' }],
          maxTokens: 200,
          responseJSON: true,
        }),
        /Model returned invalid JSON/,
      );
    });

    it('filters non-text content blocks', async () => {
      const { callWithCachedSystem, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
        '@anthropic-ai/sdk': {
          default: class {
            constructor() {}
            get messages() {
              return {
                create: async () => ({
                  content: [
                    { type: 'tool_use', text: 'should be ignored' },
                    { type: 'text', text: 'only this' },
                  ],
                  usage: { input_tokens: 5, output_tokens: 10 },
                }),
              };
            }
          },
        },
      });

      const result = await callWithCachedSystem({
        model: MODELS.HAIKU,
        system: 'test',
        messages: [{ role: 'user', content: 'hello' }],
        maxTokens: 200,
      });
      assert.equal(result.data, 'only this');
    });

    it('handles missing usage fields gracefully', async () => {
      const { callWithCachedSystem, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': {
          getAnthropicApiKey: async () => 'sk-test',
        },
        '@anthropic-ai/sdk': {
          default: class {
            constructor() {}
            get messages() {
              return {
                create: async () => ({
                  content: [{ type: 'text', text: 'hi' }],
                  usage: {},
                }),
              };
            }
          },
        },
      });

      const result = await callWithCachedSystem({
        model: MODELS.HAIKU,
        system: 'test',
        messages: [{ role: 'user', content: 'hello' }],
        maxTokens: 200,
      });
      assert.equal(result.usage.inputTokens, 0);
      assert.equal(result.usage.outputTokens, 0);
      assert.equal(result.usage.cachedInputTokens, 0);
    });
  });
});
