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

import { DynamoDBClient, GetItemCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { classifyIntent } from './router.mjs';
import { sumUsage } from './anthropic.mjs';
import { runDiscoverSources } from './tools/discoverSources.mjs';
import { runParseFilterRule } from './tools/parseFilterRule.mjs';
import { runTextPassthrough } from './tools/textPassthrough.mjs';

const dynamo = new DynamoDBClient({});
const USERS_TABLE = process.env.USERS_TABLE || 'payam-users-dev';
const DAILY_AGENT_LIMIT = 50;

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

  // Identify caller — JWT sub when auth lands, x-payam-user header for now
  const userId = event.requestContext?.authorizer?.jwt?.claims?.sub
    || event.headers?.['x-payam-user']
    || 'anonymous';

  // Enforce daily agent quota
  const quotaResult = await checkAgentQuota(userId);
  if (quotaResult.remaining <= 0) {
    return jsonResponse(429, {
      error: 'Daily agent limit reached',
      quota: { limit: DAILY_AGENT_LIMIT, remaining: 0 },
    });
  }

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
        toolResult = await runDiscoverSources({ topic, subscribedURLs, topicAffinities: payload.topicAffinities });
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

    // Decrement quota on successful call
    const updatedQuota = await decrementAgentQuota(userId);

    return jsonResponse(200, {
      intent,
      view: toolResult.view,
      followups: toolResult.followups ?? [],
      usage,
      quota: { limit: DAILY_AGENT_LIMIT, remaining: updatedQuota.remaining },
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

// --- Agent Quota ---

function todayKey() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

async function checkAgentQuota(userId) {
  const day = todayKey();
  try {
    const result = await dynamo.send(
      new GetItemCommand({
        TableName: USERS_TABLE,
        Key: { userId: { S: userId } },
        ProjectionExpression: 'agentCallsToday, agentQuotaDay',
      })
    );
    const item = result.Item;
    if (!item || item.agentQuotaDay?.S !== day) {
      return { remaining: DAILY_AGENT_LIMIT };
    }
    const used = parseInt(item.agentCallsToday?.N || '0', 10);
    return { remaining: Math.max(0, DAILY_AGENT_LIMIT - used) };
  } catch {
    // On DynamoDB failure, allow the request (fail open)
    return { remaining: DAILY_AGENT_LIMIT };
  }
}

async function decrementAgentQuota(userId) {
  const day = todayKey();
  try {
    const result = await dynamo.send(
      new UpdateItemCommand({
        TableName: USERS_TABLE,
        Key: { userId: { S: userId } },
        UpdateExpression:
          'SET agentCallsToday = if_not_exists(agentCallsToday, :zero) + :one, agentQuotaDay = :day',
        ConditionExpression: 'attribute_not_exists(agentQuotaDay) OR agentQuotaDay = :day',
        ExpressionAttributeValues: {
          ':zero': { N: '0' },
          ':one': { N: '1' },
          ':day': { S: day },
        },
        ReturnValues: 'ALL_NEW',
      })
    );
    const used = parseInt(result.Attributes?.agentCallsToday?.N || '1', 10);
    return { remaining: Math.max(0, DAILY_AGENT_LIMIT - used) };
  } catch (err) {
    if (err.name === 'ConditionalCheckFailedException') {
      // Day rolled over mid-request — reset and count as 1
      await dynamo.send(
        new UpdateItemCommand({
          TableName: USERS_TABLE,
          Key: { userId: { S: userId } },
          UpdateExpression: 'SET agentCallsToday = :one, agentQuotaDay = :day',
          ExpressionAttributeValues: {
            ':one': { N: '1' },
            ':day': { S: day },
          },
        })
      );
      return { remaining: DAILY_AGENT_LIMIT - 1 };
    }
    return { remaining: DAILY_AGENT_LIMIT };
  }
}
