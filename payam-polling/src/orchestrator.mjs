// orchestrator — EventBridge-triggered every 5 minutes.
// Scans the feed registry, picks feeds whose polling interval has elapsed
// (or whose dead-feed retry window has elapsed), and enqueues one SQS
// message per due feed for the worker Lambda to process.

import { ScanCommand } from '@aws-sdk/lib-dynamodb';
import { SQSClient, SendMessageBatchCommand } from '@aws-sdk/client-sqs';

import { ddb, TABLES } from './lib/ddb.mjs';
import { isDueForPoll } from './lib/velocity.mjs';
import { pollDedupId } from './lib/keys.mjs';

const sqs = new SQSClient({ region: process.env.AWS_REGION ?? 'us-west-2' });
const QUEUE_URL = process.env.POLL_QUEUE_URL;
const MAX_BATCH = 10;

export async function main() {
  const nowSec = Math.floor(Date.now() / 1000);
  const due = [];

  let ExclusiveStartKey;
  do {
    const page = await ddb.send(new ScanCommand({
      TableName: TABLES.registry,
      ExclusiveStartKey,
      ProjectionExpression: 'feedUrl, feedId, etag, lastModified, lastFetchedAt, velocityTier, isDead',
    }));
    for (const row of page.Items ?? []) {
      // Skip feeds with no active subscribers. subscriberCount can drift negative
      // if a removal races with an add, so guard with <= 0. Feeds that pre-date
      // the subscriberCount field (attribute_not_exists) are kept — they may be
      // legacy rows that haven't been through a subscribe/unsubscribe cycle yet.
      const count = row.subscriberCount;
      if (typeof count === 'number' && count <= 0) continue;
      if (isDueForPoll(row, nowSec)) due.push(row);
    }
    ExclusiveStartKey = page.LastEvaluatedKey;
  } while (ExclusiveStartKey);

  if (due.length === 0) {
    console.log(JSON.stringify({ event: 'orchestrator.idle', scannedAt: nowSec }));
    return { enqueued: 0 };
  }

  let enqueued = 0;
  for (let i = 0; i < due.length; i += MAX_BATCH) {
    const slice = due.slice(i, i + MAX_BATCH);
    const Entries = slice.map((row, idx) => ({
      Id: `${i + idx}`,
      MessageBody: JSON.stringify({
        feedUrl: row.feedUrl,
        feedId: row.feedId,
        etag: row.etag ?? null,
        lastModified: row.lastModified ?? null,
        velocityTier: row.velocityTier ?? 'article',
      }),
      MessageDeduplicationId: pollDedupId(row.feedUrl, row.lastFetchedAt ?? 0),
      MessageGroupId: row.velocityTier ?? 'article',
    }));
    // Standard queue ignores Dedup/Group fields; FIFO uses them. Cheap to send either way.
    try {
      const res = await sqs.send(new SendMessageBatchCommand({
        QueueUrl: QUEUE_URL,
        Entries: Entries.map(({ MessageDeduplicationId, MessageGroupId, ...rest }) => rest),
      }));
      enqueued += (res.Successful ?? []).length;
      if (res.Failed?.length) {
        console.warn(JSON.stringify({ event: 'orchestrator.enqueue_failed', failed: res.Failed }));
      }
    } catch (err) {
      console.error(JSON.stringify({ event: 'orchestrator.send_error', err: String(err) }));
    }
  }

  console.log(JSON.stringify({ event: 'orchestrator.done', enqueued, scannedAt: nowSec }));
  return { enqueued };
}
