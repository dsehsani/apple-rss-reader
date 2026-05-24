// river — GET /v1/river?since={epochSec}
// Delta-sync endpoint. Returns new feed items across all of a user's feeds
// since the provided timestamp, optionally merged with per-user read/bookmark
// state for premium users.
//
// JWT auth middleware is a Phase 2 dependency; this handler reads the
// caller's identity from the Lambda proxy claims and falls back to a header
// for local testing.

import { QueryCommand, BatchGetCommand } from '@aws-sdk/lib-dynamodb';

import { ddb, TABLES, ITEMS_BY_FETCHED_INDEX } from './lib/ddb.mjs';

const MAX_ITEMS_PER_FEED = 100;
const MAX_ITEMS_TOTAL = 500;

// Workers stamp `fetchedAt` with the time they started polling, then write
// items several seconds later. If a client refreshes during that window, its
// `lastServerTime` lands *after* the in-flight items' `fetchedAt`, and they
// become unreachable forever for that device. Re-query a grace window so
// recent items are always re-delivered; iOS dedupes by stable itemId, so the
// cost is just bandwidth, not correctness.
const SINCE_GRACE_SEC = 10 * 60;

export async function main(event) {
  // TODO(auth): re-enable 401 once JWT middleware lands. TestFlight build accepts
  // unauthenticated callers identifying themselves via the x-payam-user header.
  const userId = resolveUserId(event);
  if (!userId) return resp(400, { error: 'x-payam-user header required' });

  const since = Number(event.queryStringParameters?.since ?? 0);
  if (!Number.isFinite(since) || since < 0) {
    return resp(400, { error: 'since must be a non-negative epoch second' });
  }
  // TODO(auth): derive from JWT tier claim once available. TestFlight treats every caller as premium.
  const isPremium = true;
  const nowSec = Math.floor(Date.now() / 1000);

  const subs = await querySubscriptions(userId);
  if (subs.length === 0) {
    return resp(200, { items: [], state: [], deleted: [], serverTime: nowSec });
  }

  const feedIds = [...new Set(subs.map((s) => s.feedId).filter(Boolean))];
  const effectiveSince = Math.max(0, since - SINCE_GRACE_SEC);
  const perFeed = await Promise.all(feedIds.map((feedId) => queryItemsSince(feedId, effectiveSince)));

  let items = perFeed.flat();
  items.sort((a, b) => b.publishedAt - a.publishedAt);
  if (items.length > MAX_ITEMS_TOTAL) items = items.slice(0, MAX_ITEMS_TOTAL);

  let state = [];
  if (isPremium && items.length > 0) {
    state = await fetchItemState(userId, items.map((it) => it.itemId));
  }

  return resp(200, {
    items,
    state,
    deleted: [],
    serverTime: nowSec,
  });
}

function resolveUserId(event) {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  return claims?.sub ?? claims?.userId ?? event.headers?.['x-payam-user'] ?? null;
}

async function querySubscriptions(userId) {
  const out = [];
  let ExclusiveStartKey;
  do {
    const res = await ddb.send(new QueryCommand({
      TableName: TABLES.userFeeds,
      KeyConditionExpression: 'userId = :u',
      ExpressionAttributeValues: { ':u': userId },
      ExclusiveStartKey,
    }));
    for (const row of res.Items ?? []) out.push(row);
    ExclusiveStartKey = res.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return out;
}

async function queryItemsSince(feedId, since) {
  const res = await ddb.send(new QueryCommand({
    TableName: TABLES.items,
    IndexName: ITEMS_BY_FETCHED_INDEX,
    KeyConditionExpression: 'feedId = :f AND fetchedAt > :s',
    ExpressionAttributeValues: { ':f': feedId, ':s': since },
    Limit: MAX_ITEMS_PER_FEED,
    ScanIndexForward: false,
  }));
  return res.Items ?? [];
}

async function fetchItemState(userId, itemIds) {
  const out = [];
  for (let i = 0; i < itemIds.length; i += 100) {
    const slice = itemIds.slice(i, i + 100);
    const res = await ddb.send(new BatchGetCommand({
      RequestItems: {
        [TABLES.userItemState]: {
          Keys: slice.map((itemId) => ({ userId, itemId })),
        },
      },
    }));
    for (const row of res.Responses?.[TABLES.userItemState] ?? []) out.push(row);
  }
  return out;
}

function resp(statusCode, body) {
  return {
    statusCode,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  };
}
