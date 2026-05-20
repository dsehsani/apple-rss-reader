// EventBridge (every 5min) → This Lambda
// Queries feed_registry for feeds due for refresh, sends each to SQS.

import { SQSClient, SendMessageBatchCommand } from "@aws-sdk/client-sqs";
import { query } from "./db.mjs";

const sqs = new SQSClient({});
const QUEUE_URL = process.env.FEED_POLL_QUEUE_URL;

// Polling intervals by velocity tier (in minutes)
const POLL_INTERVALS = {
  breaking: 5,
  news: 15,
  article: 60,
  essay: 360,
  evergreen: 1440,
};

export async function main() {
  const result = await query(
    `SELECT id, feed_url, etag, last_modified, velocity_tier
     FROM feed_registry
     WHERE is_dead = FALSE
       AND (last_fetched_at IS NULL OR last_fetched_at < NOW() - make_interval(mins := $1))
     ORDER BY last_fetched_at ASC NULLS FIRST
     LIMIT 1000`,
    [5] // Minimum interval — the worker checks per-tier intervals
  );

  if (result.rows.length === 0) {
    console.log("No feeds due for refresh");
    return;
  }

  // Filter by per-tier interval
  const now = Date.now();
  const dueFeeds = result.rows; // All returned feeds are at least 5min stale

  // Send to SQS in batches of 10 (SQS limit)
  const batches = [];
  for (let i = 0; i < dueFeeds.length; i += 10) {
    batches.push(dueFeeds.slice(i, i + 10));
  }

  let enqueued = 0;
  for (const batch of batches) {
    const entries = batch.map((feed, idx) => ({
      Id: String(idx),
      MessageBody: JSON.stringify({
        feedId: feed.id,
        feedUrl: feed.feed_url,
        etag: feed.etag,
        lastModified: feed.last_modified,
        velocityTier: feed.velocity_tier,
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

  console.log(`Enqueued ${enqueued} feeds for polling`);
}
