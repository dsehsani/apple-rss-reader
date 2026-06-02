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

  describe('extractJSONObject', () => {
    it('extracts a balanced JSON object from surrounding prose', async () => {
      const { extractJSONObject } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': { getAnthropicApiKey: async () => 'sk-test' },
      });
      assert.equal(extractJSONObject('here you go: {"a":1} thanks'), '{"a":1}');
    });

    it('handles braces inside strings', async () => {
      const { extractJSONObject } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': { getAnthropicApiKey: async () => 'sk-test' },
      });
      const out = extractJSONObject('{"name":"a}b","x":{"y":2}}');
      assert.equal(out, '{"name":"a}b","x":{"y":2}}');
    });

    it('returns null when there is no object', async () => {
      const { extractJSONObject } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': { getAnthropicApiKey: async () => 'sk-test' },
      });
      assert.equal(extractJSONObject('no json here'), null);
      assert.equal(extractJSONObject(42), null);
    });
  });

  describe('callWithWebSearch', () => {
    function mockSDK(content, usage = { input_tokens: 5, output_tokens: 10 }) {
      return {
        '../src/secrets.mjs': { getAnthropicApiKey: async () => 'sk-test' },
        '@anthropic-ai/sdk': {
          default: class {
            get messages() {
              return { create: async () => ({ content, usage }) };
            }
          },
        },
      };
    }

    it('passes the web_search tool and parses JSON from mixed content blocks', async () => {
      let received;
      const { callWithWebSearch, MODELS } = await esmock('../src/anthropic.mjs', {
        '../src/secrets.mjs': { getAnthropicApiKey: async () => 'sk-test' },
        '@anthropic-ai/sdk': {
          default: class {
            get messages() {
              return {
                create: async (body) => {
                  received = body;
                  return {
                    content: [
                      { type: 'server_tool_use', name: 'web_search' },
                      { type: 'web_search_tool_result', content: [] },
                      { type: 'text', text: 'Found these: {"topic":"soccer","candidates":[]}' },
                    ],
                    usage: { input_tokens: 12, output_tokens: 8 },
                  };
                },
              };
            }
          },
        },
      });

      const result = await callWithWebSearch({
        model: MODELS.SONNET,
        system: 'find feeds',
        messages: [{ role: 'user', content: 'soccer' }],
        maxTokens: 500,
        responseJSON: true,
      });
      assert.deepEqual(result.data, { topic: 'soccer', candidates: [] });
      assert.equal(received.tools[0].type, 'web_search_20250305');
      assert.equal(received.tools[0].name, 'web_search');
      assert.equal(result.usage.inputTokens, 12);
    });

    it('returns raw text when responseJSON is false', async () => {
      const { callWithWebSearch, MODELS } = await esmock(
        '../src/anthropic.mjs',
        mockSDK([{ type: 'text', text: 'plain answer' }]),
      );
      const result = await callWithWebSearch({
        model: MODELS.SONNET,
        system: 's',
        messages: [{ role: 'user', content: 'x' }],
        maxTokens: 100,
      });
      assert.equal(result.data, 'plain answer');
    });

    it('throws when no JSON object is present', async () => {
      const { callWithWebSearch, MODELS } = await esmock(
        '../src/anthropic.mjs',
        mockSDK([{ type: 'text', text: 'sorry, nothing' }]),
      );
      await assert.rejects(
        callWithWebSearch({
          model: MODELS.SONNET,
          system: 's',
          messages: [{ role: 'user', content: 'x' }],
          maxTokens: 100,
          responseJSON: true,
        }),
        /no JSON object/,
      );
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

    it('parses JSON even when the model appends trailing prose after the object', async () => {
      // Regression: Haiku sometimes emits a valid object then keeps writing an
      // "Explanation: ..." paragraph, which caused a strict JSON.parse to throw and
      // surface as an HTTP 500 on the article-summary path.
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
                  content: [{
                    type: 'text',
                    text: '\n  "intent": "unknown",\n  "args": { "raw": "x" },\n  "confidence": 0.35\n}\n\nExplanation: This message appears to be instructing the assistant to summarize an article.',
                  }],
                  usage: { input_tokens: 10, output_tokens: 20 },
                }),
              };
            }
          },
        },
      });

      const result = await callWithCachedSystem({
        model: MODELS.HAIKU,
        system: 'test system prompt',
        messages: [{ role: 'user', content: 'summarize this' }],
        maxTokens: 200,
        responseJSON: true,
      });
      assert.deepEqual(result.data, { intent: 'unknown', args: { raw: 'x' }, confidence: 0.35 });
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

    it('throws when no JSON object can be recovered', async () => {
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
                  // Prefill is `{`; an unterminated object never closes → unrecoverable.
                  content: [{ type: 'text', text: '"intent": "explain"' }],
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
        /Model returned no JSON object/,
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
