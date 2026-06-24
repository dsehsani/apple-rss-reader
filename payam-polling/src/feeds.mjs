// feeds — POST /v1/feeds
// Subscription mutation endpoint. Body:
//   { added:   [{feedUrl, folder?}],
//     removed: [{feedUrl}] }
// Maintains payam-user-feeds rows and atomically updates subscriberCount on
// payam-feed-registry. New feed URLs get a registry row with lastFetchedAt=0
// so the next orchestrator scan picks them up immediately.

import { PutCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { SQSClient, SendMessageBatchCommand } from '@aws-sdk/client-sqs';

import { ddb, TABLES } from './lib/ddb.mjs';
import { canonicalizeFeedUrl, feedIdFor } from './lib/keys.mjs';

const sqs = new SQSClient({ region: process.env.AWS_REGION ?? 'us-west-2' });
const QUEUE_URL = process.env.POLL_QUEUE_URL;
const SQS_BATCH_MAX = 10;

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

  // Feeds that should be polled immediately (newly subscribed). The orchestrator
  // runs every 5 min, so without this nudge users wait up to that long before
  // a freshly added feed shows any items. Collected during the add loop and
  // batch-sent to SQS at the end.
  const toKickPoll = [];

  for (const entry of added) {
    try {
      const feedUrl = canonicalizeFeedUrl(entry.feedUrl);
      const feedId = feedIdFor(feedUrl);
      await ensureRegistryRow(feedUrl, feedId, nowSec);

      let inserted = false;
      try {
        await ddb.send(new TransactWriteCommand({
          TransactItems: [
            {
              Put: {
                TableName: TABLES.userFeeds,
                Item: {
                  userId,
                  feedUrl,
                  feedId,
                  folderName: entry.folder ?? null,
                  addedAt: nowSec,
                },
                ConditionExpression: 'attribute_not_exists(userId) OR attribute_not_exists(feedUrl)',
              },
            },
            {
              Update: {
                TableName: TABLES.registry,
                Key: { feedUrl },
                UpdateExpression: 'ADD subscriberCount :one',
                ExpressionAttributeValues: { ':one': 1 },
              },
            },
          ],
        }));
        inserted = true;
      } catch (err) {
        if (err?.name === 'TransactionCanceledException' &&
            err.CancellationReasons?.[0]?.Code === 'ConditionalCheckFailed') {
          // Already subscribed — no-op, don't double-increment subscriberCount.
        } else {
          throw err;
        }
      }
      if (inserted) {
        toKickPoll.push({ feedUrl, feedId });
        result.added++;
      }
    } catch (err) {
      result.errors.push({ op: 'add', feedUrl: entry.feedUrl, err: String(err) });
    }
  }

  // Best-effort SQS kick. Failures here just mean the user waits for the next
  // orchestrator tick (≤5 min) — acceptable degradation, so we log and move on
  // instead of failing the whole subscribe call.
  await kickPolls(toKickPoll);

  for (const entry of removed) {
    try {
      const feedUrl = canonicalizeFeedUrl(entry.feedUrl);
      let didDelete = false;
      try {
        await ddb.send(new TransactWriteCommand({
          TransactItems: [
            {
              Delete: {
                TableName: TABLES.userFeeds,
                Key: { userId, feedUrl },
                ConditionExpression: 'attribute_exists(userId)',
              },
            },
            {
              Update: {
                TableName: TABLES.registry,
                Key: { feedUrl },
                UpdateExpression: 'ADD subscriberCount :neg',
                ConditionExpression: 'subscriberCount > :zero',
                ExpressionAttributeValues: { ':neg': -1, ':zero': 0 },
              },
            },
          ],
        }));
        didDelete = true;
      } catch (err) {
        if (err?.name === 'TransactionCanceledException' &&
            err.CancellationReasons?.[0]?.Code === 'ConditionalCheckFailed') {
          // Already unsubscribed — no-op.
        } else {
          throw err;
        }
      }
      if (didDelete) {
        result.removed++;
      }
    } catch (err) {
      result.errors.push({ op: 'remove', feedUrl: entry.feedUrl, err: String(err) });
    }
  }

  return resp(200, result);
}

// Mirrors the orchestrator's enqueue shape so the worker handles both inputs
// identically. etag/lastModified are null on a freshly-subscribed feed; the
// worker just skips the conditional-GET headers and does a full fetch.
async function kickPolls(rows) {
  if (!QUEUE_URL || rows.length === 0) return;
  for (let i = 0; i < rows.length; i += SQS_BATCH_MAX) {
    const slice = rows.slice(i, i + SQS_BATCH_MAX);
    const Entries = slice.map((row, idx) => ({
      Id: `${i + idx}`,
      MessageBody: JSON.stringify({
        feedUrl: row.feedUrl,
        feedId: row.feedId,
        etag: null,
        lastModified: null,
        velocityTier: 'article',
      }),
    }));
    try {
      const res = await sqs.send(new SendMessageBatchCommand({
        QueueUrl: QUEUE_URL,
        Entries,
      }));
      if (res.Failed?.length) {
        console.warn(JSON.stringify({ event: 'feeds.kick_partial_failure', failed: res.Failed }));
      }
    } catch (err) {
      console.warn(JSON.stringify({ event: 'feeds.kick_enqueue_failed', count: slice.length, err: String(err) }));
    }
  }
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
