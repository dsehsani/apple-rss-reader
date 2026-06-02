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

const fakeClassification = (intent, args = {}) => ({
  intent,
  args,
  confidence: 0.9,
  usage: fakeUsage,
});

const fakeToolResult = (type = 'text', payload = { content: 'hello' }) => ({
  view: { type, payload },
  usage: fakeUsage,
  followups: [],
});

function makeAgent({ classifyResult, discoverResult, filterResult, textResult, classifyError }) {
  return esmock('../src/agent.mjs', {
    '../src/router.mjs': {
      classifyIntent: classifyError
        ? async () => { throw classifyError; }
        : async () => classifyResult,
    },
    '../src/tools/discoverSources.mjs': {
      runDiscoverSources: async () => discoverResult || fakeToolResult('card_list', { topic: 'AI', cards: [] }),
    },
    '../src/tools/parseFilterRule.mjs': {
      runParseFilterRule: async () => filterResult || fakeToolResult('rule_card', {}),
    },
    '../src/tools/textPassthrough.mjs': {
      runTextPassthrough: async () => textResult || fakeToolResult(),
    },
    '../src/anthropic.mjs': {
      sumUsage: (parts) => ({
        model: parts.map((p) => p.model).join('+'),
        inputTokens: parts.reduce((s, p) => s + (p.inputTokens || 0), 0),
        cachedInputTokens: parts.reduce((s, p) => s + (p.cachedInputTokens || 0), 0),
        cacheCreationInputTokens: parts.reduce((s, p) => s + (p.cacheCreationInputTokens || 0), 0),
        outputTokens: parts.reduce((s, p) => s + (p.outputTokens || 0), 0),
      }),
    },
  });
}

function postEvent(body) {
  return {
    requestContext: { http: { method: 'POST' } },
    body: JSON.stringify(body),
    isBase64Encoded: false,
  };
}

function parseResponse(resp) {
  return JSON.parse(resp.body);
}

describe('agent main()', () => {
  it('rejects non-POST methods', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main({
      requestContext: { http: { method: 'GET' } },
    });
    assert.equal(resp.statusCode, 405);
  });

  it('rejects invalid JSON body', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main({
      requestContext: { http: { method: 'POST' } },
      body: 'not-json{{{',
      isBase64Encoded: false,
    });
    assert.equal(resp.statusCode, 400);
    assert.ok(parseResponse(resp).error.includes('Invalid JSON'));
  });

  it('rejects missing messages', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({}));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects empty messages array', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({ messages: [] }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects invalid message role', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({ messages: [{ role: 'invalid', content: 'hi' }] }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects empty message content', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({ messages: [{ role: 'user', content: '  ' }] }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects invalid articleContext', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hi' }],
      articleContext: 'not-an-object',
    }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects articleContext with missing fields', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hi' }],
      articleContext: { title: 'ok', feedName: 123, content: 'text' },
    }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects non-array subscriptions', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hi' }],
      subscriptions: 'not-array',
    }));
    assert.equal(resp.statusCode, 400);
  });

  it('handles source_discovery with topic', async () => {
    const discoverResult = fakeToolResult('card_list', { topic: 'AI', cards: [] });
    const { main } = await makeAgent({
      classifyResult: fakeClassification('source_discovery', { topic: 'AI' }),
      discoverResult,
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'find feeds about AI' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'source_discovery');
    assert.equal(body.view.type, 'card_list');
  });

  it('source_discovery without topic falls to text passthrough', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('source_discovery', { topic: '' }),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'find feeds' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'explain');
    assert.equal(body.view.type, 'text');
  });

  it('source_discovery without topic (no args) falls to text passthrough', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('source_discovery', {}),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'find feeds' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'explain');
  });

  it('handles filter_rule intent', async () => {
    const filterResult = fakeToolResult('rule_card', { displayText: 'Hide opinion' });
    const { main } = await makeAgent({
      classifyResult: fakeClassification('filter_rule', { text: 'hide opinions' }),
      filterResult,
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hide opinions' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'filter_rule');
    assert.equal(body.view.type, 'rule_card');
  });

  it('handles find_similar intent (falls to text)', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('find_similar', {}),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'find similar' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'find_similar');
    assert.equal(body.view.type, 'text');
  });

  it('handles feed_audit intent (falls to text)', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('feed_audit', {}),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'audit my feeds' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'feed_audit');
    assert.equal(body.view.type, 'text');
  });

  it('handles default/explain intent', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('explain', { question: 'how?' }),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'how do I add a feed?' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'explain');
    assert.equal(body.view.type, 'text');
  });

  it('handles unknown intent (default case)', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('unknown', {}),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'blah blah' }],
    }));
    assert.equal(resp.statusCode, 200);
    const body = parseResponse(resp);
    assert.equal(body.intent, 'unknown');
  });

  it('returns 500 on internal errors with error view', async () => {
    const { main } = await makeAgent({
      classifyError: new Error('API rate limit exceeded'),
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hello' }],
    }));
    assert.equal(resp.statusCode, 500);
    const body = parseResponse(resp);
    assert.equal(body.error, 'API rate limit exceeded');
    assert.equal(body.intent, 'unknown');
    assert.equal(body.view.type, 'text');
  });

  it('includes followups and quota in response', async () => {
    const toolResult = {
      view: { type: 'text', payload: { content: 'hi' } },
      usage: fakeUsage,
      followups: ['ask about feeds', 'try filter'],
    };
    const { main } = await makeAgent({
      classifyResult: fakeClassification('explain'),
      textResult: toolResult,
    });

    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hello' }],
    }));
    const body = parseResponse(resp);
    assert.deepEqual(body.followups, ['ask about feeds', 'try filter']);
    assert.equal(body.quota, null);
  });

  it('handles base64-encoded body', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('explain'),
    });

    const payload = JSON.stringify({ messages: [{ role: 'user', content: 'hello' }] });
    const resp = await main({
      requestContext: { http: { method: 'POST' } },
      body: Buffer.from(payload).toString('base64'),
      isBase64Encoded: true,
    });
    assert.equal(resp.statusCode, 200);
  });

  it('handles empty body', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('explain'),
    });
    const resp = await main({
      requestContext: { http: { method: 'POST' } },
      body: null,
      isBase64Encoded: false,
    });
    assert.equal(resp.statusCode, 400);
  });

  it('handles httpMethod fallback for method detection', async () => {
    const { main } = await makeAgent({
      classifyResult: fakeClassification('explain'),
    });
    const resp = await main({
      httpMethod: 'GET',
    });
    assert.equal(resp.statusCode, 405);
  });

  it('filter_rule uses last message content when args.text is missing', async () => {
    let capturedArgs;
    const { main } = await esmock('../src/agent.mjs', {
      '../src/router.mjs': {
        classifyIntent: async () => fakeClassification('filter_rule', {}),
      },
      '../src/tools/discoverSources.mjs': {
        runDiscoverSources: async () => fakeToolResult(),
      },
      '../src/tools/parseFilterRule.mjs': {
        runParseFilterRule: async (args) => {
          capturedArgs = args;
          return fakeToolResult('rule_card', {});
        },
      },
      '../src/tools/textPassthrough.mjs': {
        runTextPassthrough: async () => fakeToolResult(),
      },
      '../src/anthropic.mjs': {
        sumUsage: (parts) => ({
          model: parts.map((p) => p.model).join('+'),
          inputTokens: 0,
          cachedInputTokens: 0,
          cacheCreationInputTokens: 0,
          outputTokens: 0,
        }),
      },
    });

    await main(postEvent({
      messages: [{ role: 'user', content: 'hide opinions please' }],
    }));
    assert.equal(capturedArgs.text, 'hide opinions please');
  });

  it('passes subscriptions to runDiscoverSources', async () => {
    let capturedArgs;
    const { main } = await esmock('../src/agent.mjs', {
      '../src/router.mjs': {
        classifyIntent: async () => fakeClassification('source_discovery', { topic: 'AI' }),
      },
      '../src/tools/discoverSources.mjs': {
        runDiscoverSources: async (args) => {
          capturedArgs = args;
          return fakeToolResult('card_list', { topic: 'AI', cards: [] });
        },
      },
      '../src/tools/parseFilterRule.mjs': {
        runParseFilterRule: async () => fakeToolResult(),
      },
      '../src/tools/textPassthrough.mjs': {
        runTextPassthrough: async () => fakeToolResult(),
      },
      '../src/anthropic.mjs': {
        sumUsage: (parts) => ({
          model: parts.map((p) => p.model).join('+'),
          inputTokens: 0,
          cachedInputTokens: 0,
          cacheCreationInputTokens: 0,
          outputTokens: 0,
        }),
      },
    });

    await main(postEvent({
      messages: [{ role: 'user', content: 'find AI feeds' }],
      subscriptions: [{ title: 'Test', feedURL: 'https://test.com/feed' }],
    }));
    assert.deepEqual(capturedArgs.subscribedURLs, ['https://test.com/feed']);
  });

  it('validates message is an object', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({ messages: ['not-an-object'] }));
    assert.equal(resp.statusCode, 400);
  });

  it('rejects articleContext as array', async () => {
    const { main } = await makeAgent({ classifyResult: fakeClassification('explain') });
    const resp = await main(postEvent({
      messages: [{ role: 'user', content: 'hi' }],
      articleContext: ['array'],
    }));
    assert.equal(resp.statusCode, 400);
  });
});
