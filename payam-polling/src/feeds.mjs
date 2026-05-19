// feeds — POST /v1/feeds
// Subscription mutation endpoint. Body:
//   { added:   [{feedUrl, folder?}],
//     removed: [{feedUrl}] }
// Maintains payam-user-feeds rows and atomically updates subscriberCount on
// payam-feed-registry. New feed URLs get a registry row with lastFetchedAt=0
// so the next orchestrator scan picks them up immediately.

import { PutCommand, DeleteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

import { ddb, TABLES } from './lib/ddb.mjs';
import { canonicalizeFeedUrl, feedIdFor } from './lib/keys.mjs';

export async function main(event) {
  const userId = resolveUserId(event);
  if (!userId) return resp(401, { error: 'unauthorized' });

  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return resp(400, { error: 'invalid JSON body' });
  }

  const added = Array.isArray(body.added) ? body.added : [];
  const removed = Array.isArray(body.removed) ? body.removed : [];
  const nowSec = Math.floor(Date.now() / 1000);

  const result = { added: 0, removed: 0, errors: [] };

  for (const entry of added) {
    try {
      const feedUrl = canonicalizeFeedUrl(entry.feedUrl);
      const feedId = feedIdFor(feedUrl);
      await ensureRegistryRow(feedUrl, feedId, nowSec);

      let inserted = false;
      try {
        await ddb.send(new PutCommand({
          TableName: TABLES.userFeeds,
          Item: {
            userId,
            feedUrl,
            feedId,
            folderName: entry.folder ?? null,
            addedAt: nowSec,
          },
          ConditionExpression: 'attribute_not_exists(userId) OR attribute_not_exists(feedUrl)',
        }));
        inserted = true;
      } catch (err) {
        if (err?.name !== 'ConditionalCheckFailedException') throw err;
        // Already subscribed — no-op, don't double-increment subscriberCount.
      }
      if (inserted) {
        await ddb.send(new UpdateCommand({
          TableName: TABLES.registry,
          Key: { feedUrl },
          UpdateExpression: 'ADD subscriberCount :one',
          ExpressionAttributeValues: { ':one': 1 },
        }));
        result.added++;
      }
    } catch (err) {
      result.errors.push({ op: 'add', feedUrl: entry.feedUrl, err: String(err) });
    }
  }

  for (const entry of removed) {
    try {
      const feedUrl = canonicalizeFeedUrl(entry.feedUrl);
      let didDelete = false;
      try {
        await ddb.send(new DeleteCommand({
          TableName: TABLES.userFeeds,
          Key: { userId, feedUrl },
          ConditionExpression: 'attribute_exists(userId)',
        }));
        didDelete = true;
      } catch (err) {
        if (err?.name !== 'ConditionalCheckFailedException') throw err;
      }
      if (didDelete) {
        await ddb.send(new UpdateCommand({
          TableName: TABLES.registry,
          Key: { feedUrl },
          UpdateExpression: 'ADD subscriberCount :neg',
          ExpressionAttributeValues: { ':neg': -1 },
        }));
        result.removed++;
      }
    } catch (err) {
      result.errors.push({ op: 'remove', feedUrl: entry.feedUrl, err: String(err) });
    }
  }

  return resp(200, result);
}

async function ensureRegistryRow(feedUrl, feedId, nowSec) {
  try {
    await ddb.send(new PutCommand({
      TableName: TABLES.registry,
      Item: {
        feedUrl,
        feedId,
        velocityTier: 'article',
        subscriberCount: 0,
        isDead: false,
        consecutiveFailures: 0,
        lastFetchedAt: 0,
        createdAt: nowSec,
      },
      ConditionExpression: 'attribute_not_exists(feedUrl)',
    }));
  } catch (err) {
    if (err?.name === 'ConditionalCheckFailedException') return;
    throw err;
  }
}

function resolveUserId(event) {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  return claims?.sub ?? claims?.userId ?? event.headers?.['x-payam-user'] ?? null;
}

function resp(statusCode, body) {
  return {
    statusCode,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  };
}
