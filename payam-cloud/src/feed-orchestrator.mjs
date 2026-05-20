// EventBridge (every 5min) → This Lambda
// Queries feed_registry for feeds due for refresh, sends each to SQS.
// Respects per-tier polling intervals and dead feed retry windows.

import { SQSClient, SendMessageBatchCommand } from "@aws-sdk/client-sqs";
import { query } from "./db.mjs";

const sqs = new SQSClient({});
const QUEUE_URL = process.env.FEED_POLL_QUEUE_URL;

// Polling intervals by velocity tier (in seconds)
const POLL_INTERVALS = {
  breaking:  5 * 60,
  news:      15 * 60,
  article:   60 * 60,
  essay:     6 * 60 * 60,
  evergreen: 24 * 60 * 60,
};

const DEAD_RETRY_SECONDS = 24 * 60 * 60;

function isDueForPoll(feed, nowSec) {
  const lastFetched = feed.last_fetched_epoch ?? 0;
  if (feed.is_dead) {
    return nowSec - lastFetched > DEAD_RETRY_SECONDS;
  }
  const interval = POLL_INTERVALS[feed.velocity_tier] ?? POLL_INTERVALS.article;
  return nowSec - lastFetched >= interval;
}

export async function main() {
  // Fetch all non-dead feeds + dead feeds eligible for daily retry
  const result = await query(
    `SELECT id, feed_url, etag, last_modified, velocity_tier, is_dead,
            subscriber_count, consecutive_failures,
            EXTRACT(EPOCH FROM COALESCE(last_fetched_at, '1970-01-01'::timestamptz)) AS last_fetched_epoch
     FROM feed_registry
     WHERE is_dead = FALSE
        OR (is_dead = TRUE AND last_fetched_at < NOW() - INTERVAL '24 hours')
     ORDER BY last_fetched_at ASC NULLS FIRST
     LIMIT 1000`
  );

  if (result.rows.length === 0) {
    console.log("No feeds due for refresh");
    return;
  }

  // Filter by per-tier polling interval
  const nowSec = Date.now() / 1000;
  const dueFeeds = result.rows.filter((f) => isDueForPoll(f, nowSec));

  if (dueFeeds.length === 0) {
    console.log("No feeds due for refresh (all within tier interval)");
    return;
  }

  // Send to SQS in batches of 10 (SQS limit)
  let enqueued = 0;
  for (let i = 0; i < dueFeeds.length; i += 10) {
    const batch = dueFeeds.slice(i, i + 10);
    const entries = batch.map((feed, idx) => ({
      Id: String(idx),
      MessageBody: JSON.stringify({
        feedId: feed.id,
        feedUrl: feed.feed_url,
        etag: feed.etag,
        lastModified: feed.last_modified,
        velocityTier: feed.velocity_tier,
        subscriberCount: feed.subscriber_count ?? 0,
        isDead: feed.is_dead,
      }),
    }));

    await sqs.send(
      new SendMessageBatchCommand({
        QueueUrl: QUEUE_URL,
        Entries: entries,
      })
    );
    enqueued += entries.length;
  }

  console.log(`Enqueued ${enqueued} feeds for polling (${result.rows.length - dueFeeds.length} skipped — within tier interval)`);
}
