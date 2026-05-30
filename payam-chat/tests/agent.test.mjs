import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { main } from '../src/agent.mjs';

// These tests cover the validation & routing logic in agent.mjs.
// External calls (classifyIntent, tool runners) are NOT mocked here —
// tests that hit the Anthropic API are skipped unless ANTHROPIC_API_KEY is set.

function makeEvent(body, method = 'POST') {
  return {
    httpMethod: method,
    body: JSON.stringify(body),
    isBase64Encoded: false,
  };
}

function parseResponse(res) {
  return { status: res.statusCode, body: JSON.parse(res.body) };
}

describe('agent.main — validation', () => {
  it('rejects non-POST methods', async () => {
    const res = await main({ httpMethod: 'GET', body: null });
    const { status, body } = parseResponse(res);
    assert.equal(status, 405);
    assert.ok(body.error.includes('Method not allowed'));
  });

  it('rejects invalid JSON', async () => {
    const res = await main({ httpMethod: 'POST', body: 'not json', isBase64Encoded: false });
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('Invalid JSON'));
  });

  it('rejects missing messages', async () => {
    const res = await main(makeEvent({}));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('messages'));
  });

  it('rejects empty messages array', async () => {
    const res = await main(makeEvent({ messages: [] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('non-empty'));
  });

  it('rejects messages with invalid role', async () => {
    const res = await main(makeEvent({ messages: [{ role: 'hacker', content: 'hi' }] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('role'));
  });

  it('rejects messages with empty content', async () => {
    const res = await main(makeEvent({ messages: [{ role: 'user', content: '' }] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('content'));
  });

  it('rejects messages with whitespace-only content', async () => {
    const res = await main(makeEvent({ messages: [{ role: 'user', content: '   ' }] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('content'));
  });

  it('rejects non-object message entries', async () => {
    const res = await main(makeEvent({ messages: ['hello'] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('object'));
  });

  it('rejects null message entries', async () => {
    const res = await main(makeEvent({ messages: [null] }));
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
  });

  it('rejects invalid articleContext (array)', async () => {
    const res = await main(
      makeEvent({
        messages: [{ role: 'user', content: 'hi' }],
        articleContext: [1, 2, 3],
      }),
    );
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('articleContext'));
  });

  it('rejects articleContext with missing fields', async () => {
    const res = await main(
      makeEvent({
        messages: [{ role: 'user', content: 'hi' }],
        articleContext: { title: 'Test' },
      }),
    );
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('articleContext'));
  });

  it('rejects non-array subscriptions', async () => {
    const res = await main(
      makeEvent({
        messages: [{ role: 'user', content: 'hi' }],
        subscriptions: 'not an array',
      }),
    );
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('subscriptions'));
  });

  it('accepts valid messages with all roles', async () => {
    // This will fail at the classifyIntent step (no API key), but should pass validation
    const res = await main(
      makeEvent({
        messages: [
          { role: 'system', content: 'be helpful' },
          { role: 'user', content: 'hello' },
          { role: 'assistant', content: 'hi there' },
          { role: 'user', content: 'thanks' },
        ],
      }),
    );
    // Should get past validation — either 200 or 500 (API call failure)
    assert.ok(res.statusCode !== 400, 'Valid payload should pass validation');
  });

  it('handles base64-encoded body', async () => {
    const body = JSON.stringify({ messages: [] });
    const encoded = Buffer.from(body).toString('base64');
    const res = await main({ httpMethod: 'POST', body: encoded, isBase64Encoded: true });
    const { status, body: resBody } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(resBody.error.includes('non-empty'));
  });

  it('handles empty body', async () => {
    const res = await main({ httpMethod: 'POST', body: '', isBase64Encoded: false });
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
    assert.ok(body.error.includes('messages'));
  });

  it('handles null body', async () => {
    const res = await main({ httpMethod: 'POST', body: null, isBase64Encoded: false });
    const { status, body } = parseResponse(res);
    assert.equal(status, 400);
  });

  it('returns JSON content-type header', async () => {
    const res = await main(makeEvent({}));
    assert.equal(res.headers['Content-Type'], 'application/json');
  });

  it('detects method from requestContext.http.method', async () => {
    const res = await main({
      requestContext: { http: { method: 'GET' } },
      body: null,
    });
    assert.equal(res.statusCode, 405);
  });
});
