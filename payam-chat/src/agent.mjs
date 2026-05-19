// Entry point for POST /v1/agent — the action-first agent endpoint.
//
// Pipeline:
//   1. Validate POST body.
//   2. Classify intent (Haiku, cached system prompt).
//   3. Dispatch to a tool that returns { view, usage }.
//   4. Wrap in the discriminated-union envelope.
//
// Auth + DynamoDB quota are NOT enforced in this first iteration; the envelope
// surfaces a quota: null sentinel so the iOS client can render its banner code path
// once the backend stub lands.

import { classifyIntent } from './router.mjs';
import { sumUsage } from './anthropic.mjs';
import { runDiscoverSources } from './tools/discoverSources.mjs';
import { runParseFilterRule } from './tools/parseFilterRule.mjs';
import { runTextPassthrough } from './tools/textPassthrough.mjs';

const ALLOWED_ROLES = new Set(['user', 'assistant', 'system']);

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function readBody(event) {
  if (!event.body) return '';
  if (event.isBase64Encoded) return Buffer.from(event.body, 'base64').toString('utf8');
  return event.body;
}

function method(event) {
  return (event?.requestContext?.http?.method ?? event?.httpMethod ?? '').toUpperCase();
}

function validate(payload) {
  if (!Array.isArray(payload.messages) || payload.messages.length === 0) {
    return 'messages must be a non-empty array of { role, content }';
  }
  for (let i = 0; i < payload.messages.length; i++) {
    const m = payload.messages[i];
    if (!m || typeof m !== 'object') return `messages[${i}] must be an object`;
    if (typeof m.role !== 'string' || !ALLOWED_ROLES.has(m.role)) {
      return `messages[${i}].role must be user|assistant|system`;
    }
    if (typeof m.content !== 'string' || m.content.trim().length === 0) {
      return `messages[${i}].content must be a non-empty string`;
    }
  }
  if (payload.articleContext != null) {
    const ctx = payload.articleContext;
    if (typeof ctx !== 'object' || Array.isArray(ctx)) {
      return 'articleContext must be an object with title, feedName, content';
    }
    const { title, feedName, content } = ctx;
    if (typeof title !== 'string' || typeof feedName !== 'string' || typeof content !== 'string') {
      return 'articleContext must include string fields title, feedName, content';
    }
  }
  if (payload.subscriptions != null && !Array.isArray(payload.subscriptions)) {
    return 'subscriptions must be an array of { title, feedURL }';
  }
  return null;
}

export async function main(event) {
  if (method(event) !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed. Use POST.' });
  }

  let payload;
  try {
    const raw = readBody(event);
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  const err = validate(payload);
  if (err) return jsonResponse(400, { error: err });

  try {
    const classification = await classifyIntent(payload.messages, payload.articleContext);
    const subscriptions = payload.subscriptions ?? [];
    const subscribedURLs = subscriptions.map((s) => s.feedURL).filter(Boolean);

    let toolResult;
    let intent = classification.intent;

    switch (intent) {
      case 'source_discovery': {
        const topic = (classification.args?.topic || '').toString().trim();
        if (!topic) {
          toolResult = await runTextPassthrough({
            messages: payload.messages,
            articleContext: payload.articleContext,
          });
          intent = 'explain';
          break;
        }
        toolResult = await runDiscoverSources({ topic, subscribedURLs });
        break;
      }
      case 'filter_rule': {
        const text = (classification.args?.text || payload.messages.at(-1)?.content || '').toString();
        toolResult = await runParseFilterRule({ text, subscriptions });
        break;
      }
      case 'find_similar':
      case 'feed_audit': {
        // Implemented in Phase 2 — for now fall through to a typed text view so the
        // UI can render a "coming soon" message rather than break.
        toolResult = await runTextPassthrough({
          messages: payload.messages,
          articleContext: payload.articleContext,
        });
        break;
      }
      default: {
        toolResult = await runTextPassthrough({
          messages: payload.messages,
          articleContext: payload.articleContext,
        });
      }
    }

    const usage = sumUsage([classification.usage, toolResult.usage]);

    return jsonResponse(200, {
      intent,
      view: toolResult.view,
      followups: toolResult.followups ?? [],
      usage,
      quota: null, // populated once the DynamoDB usage table lands
    });
  } catch (e) {
    console.error('Agent error:', e.message);
    return jsonResponse(500, {
      error: e.message || 'Agent failed',
      intent: 'unknown',
      view: { type: 'text', payload: { content: 'Something went wrong on the assistant side. Try again in a moment.' } },
      usage: null,
      quota: null,
    });
  }
}
