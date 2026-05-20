// SQS → This Lambda (1 per feed URL)
// Fetches a single feed with conditional GET, diffs against existing items,
// inserts new items, re-infers velocity tier, handles dead feed detection,
// enqueues pre-extraction for popular feeds, and notifies subscribers via APNs.

import { query } from "./db.mjs";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";
import crypto from "node:crypto";
import Parser from "rss-parser";

const sqs = new SQSClient({});
const sns = new SNSClient({});
const dynamo = new DynamoDBClient({});

const PLATFORM_ARN = process.env.SNS_PLATFORM_ARN;
const DEVICE_TOKENS_TABLE = process.env.DEVICE_TOKENS_TABLE || "payam-device-tokens";
const EXTRACTION_LIGHT_QUEUE_URL = process.env.EXTRACTION_LIGHT_QUEUE_URL;

const parser = new Parser({
  timeout: 15_000,
  headers: {
    "User-Agent": "Payam/1.0 RSS Reader (https://payam.app)",
    Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
  },
  customFields: {
    item: [
      ["media:thumbnail", "mediaThumbnail", { keepArray: false }],
      ["media:content", "mediaContent", { keepArray: false }],
      ["enclosure"],
    ],
  },
});

// Velocity tier inference — matches Darius's payam-polling/src/lib/velocity.mjs
// and iOS FeedIngestService.inferVelocityTier
function inferVelocityTier(itemsCount, daySpanSeconds) {
  const days = Math.max(1, daySpanSeconds / 86400);
  const perDay = itemsCount / days;
  if (perDay >= 50) return "breaking";
  if (perDay >= 10) return "news";
  if (perDay >= 1) return "article";
  if (perDay >= 0.15) return "essay";
  return "evergreen";
}

export async function main(event) {
  for (const record of event.Records) {
    const msg = JSON.parse(record.body);
    await processFeed(msg);
  }
}

async function processFeed({ feedId, feedUrl, etag, lastModified, velocityTier, subscriberCount, isDead }) {
  try {
    // Conditional GET
    const headers = {
      "User-Agent": "Payam/1.0 RSS Reader (https://payam.app)",
      Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
    };
    if (etag) headers["If-None-Match"] = etag;
    if (lastModified) headers["If-Modified-Since"] = lastModified;

    const response = await fetch(feedUrl, {
      headers,
      signal: AbortSignal.timeout(15_000),
    });

    // Update last_fetched_at regardless of result
    await query(
      `UPDATE feed_registry SET last_fetched_at = NOW() WHERE id = $1`,
      [feedId]
    );

    if (response.status === 304) {
      // Not modified — reset failures on successful contact
      if (isDead) {
        await resetDeadFeed(feedId);
      }
      return;
    }

    if (!response.ok) {
      await recordFailure(feedId, feedUrl, response.status);
      return;
    }

    // Successful fetch — reset failures if previously dead
    if (isDead) {
      await resetDeadFeed(feedId);
    } else {
      // Reset consecutive failures on success
      await query(
        `UPDATE feed_registry SET consecutive_failures = 0 WHERE id = $1 AND consecutive_failures > 0`,
        [feedId]
      );
    }

    const xml = await response.text();
    const newEtag = response.headers.get("etag");
    const newLastModified = response.headers.get("last-modified");

    // Update etag/last-modified
    if (newEtag || newLastModified) {
      await query(
        `UPDATE feed_registry SET etag = COALESCE($2, etag), last_modified = COALESCE($3, last_modified) WHERE id = $1`,
        [feedId, newEtag, newLastModified]
      );
    }

    // Parse feed with rss-parser
    let feed;
    try {
      feed = await parser.parseString(xml);
    } catch (parseErr) {
      console.warn(`Parse failed for ${feedUrl}: ${parseErr.message}`);
      await recordFailure(feedId, feedUrl, "PARSE_ERROR");
      return;
    }

    // Update feed title/description if missing
    if (feed.title || feed.description) {
      await query(
        `UPDATE feed_registry SET
           title = COALESCE(NULLIF($2, ''), title),
           description = COALESCE(NULLIF($3, ''), description),
           image_url = COALESCE(NULLIF($4, ''), image_url)
         WHERE id = $1`,
        [feedId, feed.title || "", feed.description || "", feed.image?.url || feed.itunes?.image || ""]
      );
    }

    // Convert parsed items to our format
    const items = (feed.items || [])
      .filter((item) => item.title?.trim() && (item.link?.trim() || item.guid?.trim()))
      .map((item) => {
        const link = item.link?.trim() || item.guid?.trim();
        const id = deterministicUUID(feedId, link);
        return {
          id,
          title: item.title.trim(),
          link,
          publishedAt: item.pubDate ? new Date(item.pubDate) : item.isoDate ? new Date(item.isoDate) : new Date(),
          excerpt: item.contentSnippet?.substring(0, 500)?.trim() || "",
          imageUrl: extractImage(item),
          audioUrl: extractAudio(item),
          videoUrl: null,
          author: item.creator || item["dc:creator"] || item.author || null,
        };
      });

    if (items.length === 0) return;

    // Diff against existing items (by link within this feed)
    const links = items.map((i) => i.link);
    const existing = await query(
      `SELECT link FROM feed_items WHERE feed_id = $1 AND link = ANY($2)`,
      [feedId, links]
    );
    const existingLinks = new Set(existing.rows.map((r) => r.link));
    const newItems = items.filter((i) => !existingLinks.has(i.link));

    if (newItems.length === 0) return;

    // Insert new items
    for (const item of newItems) {
      await query(
        `INSERT INTO feed_items (id, feed_id, title, link, published_at, fetched_at, excerpt, image_url, audio_url, video_url, author, velocity_tier)
         VALUES ($1, $2, $3, $4, $5, NOW(), $6, $7, $8, $9, $10, $11)
         ON CONFLICT (feed_id, link) DO NOTHING`,
        [
          item.id, feedId, item.title, item.link,
          item.publishedAt, item.excerpt, item.imageUrl,
          item.audioUrl, item.videoUrl, item.author, velocityTier,
        ]
      );
    }

    console.log(`Inserted ${newItems.length} items from ${feedUrl}`);

    // Re-infer velocity tier from last 7 days of items
    await reInferVelocityTier(feedId);

    // Pre-extract for popular feeds
    if (subscriberCount >= 3 && ["breaking", "news", "article"].includes(velocityTier)) {
      await enqueuePreExtraction(newItems);
    }

    // Update last_item_at
    const latestPub = newItems.reduce((max, i) => i.publishedAt > max ? i.publishedAt : max, newItems[0].publishedAt);
    await query(
      `UPDATE feed_registry SET last_item_at = GREATEST(last_item_at, $2) WHERE id = $1`,
      [feedId, latestPub]
    );

    // Notify subscribers
    await notifySubscribers(feedId);
  } catch (err) {
    console.error(`Error processing feed ${feedUrl}:`, err.message);
    await recordFailure(feedId, feedUrl, "EXCEPTION");
  }
}

// --- Dead Feed Detection ---

async function recordFailure(feedId, feedUrl, reason) {
  console.warn(`Feed ${feedUrl} failed: ${reason}`);
  const result = await query(
    `UPDATE feed_registry
     SET consecutive_failures = consecutive_failures + 1
     WHERE id = $1
     RETURNING consecutive_failures`,
    [feedId]
  );

  const failures = result.rows[0]?.consecutive_failures ?? 0;
  if (failures >= 3) {
    await query(
      `UPDATE feed_registry SET is_dead = TRUE WHERE id = $1`,
      [feedId]
    );
    console.warn(`Feed ${feedUrl} marked dead after ${failures} consecutive failures`);
  }
}

async function resetDeadFeed(feedId) {
  await query(
    `UPDATE feed_registry SET is_dead = FALSE, consecutive_failures = 0 WHERE id = $1`,
    [feedId]
  );
}

// --- Velocity Re-inference ---

async function reInferVelocityTier(feedId) {
  const result = await query(
    `SELECT COUNT(*) AS item_count,
            EXTRACT(EPOCH FROM (MAX(published_at) - MIN(published_at))) AS day_span_sec
     FROM feed_items
     WHERE feed_id = $1 AND published_at > NOW() - INTERVAL '7 days'`,
    [feedId]
  );

  const row = result.rows[0];
  if (!row || row.item_count < 2) return; // Not enough data to infer

  const newTier = inferVelocityTier(parseInt(row.item_count), parseFloat(row.day_span_sec) || 86400);

  await query(
    `UPDATE feed_registry SET velocity_tier = $2 WHERE id = $1 AND velocity_tier != $2`,
    [feedId, newTier]
  );
}

// --- Pre-extraction for popular feeds ---

async function enqueuePreExtraction(items) {
  if (!EXTRACTION_LIGHT_QUEUE_URL) return;

  // Pre-extract up to 5 newest items
  const toExtract = items.slice(0, 5);
  for (const item of toExtract) {
    const urlHash = crypto.createHash("sha256").update(item.link).digest("hex").substring(0, 64);
    try {
      await sqs.send(
        new SendMessageCommand({
          QueueUrl: EXTRACTION_LIGHT_QUEUE_URL,
          MessageBody: JSON.stringify({ urlHash, url: item.link, feedId: item.id, preExtract: true }),
        })
      );
    } catch (err) {
      console.warn(`Pre-extraction enqueue failed for ${item.link}:`, err.message);
    }
  }
}

// --- Image/Audio Extraction from rss-parser output ---

function extractImage(item) {
  // Media thumbnail
  if (item.mediaThumbnail?.$.url) return item.mediaThumbnail.$.url;

  // Media content (non-audio)
  if (item.mediaContent?.$.url && !item.mediaContent.$.type?.startsWith("audio/")) {
    return item.mediaContent.$.url;
  }

  // Enclosure with image type
  if (item.enclosure?.type?.startsWith("image/")) return item.enclosure.url;

  // First img in content HTML
  const content = item["content:encoded"] || item.content || "";
  const imgMatch = content.match(/<img[^>]*src=["']([^"']+)["']/i);
  if (imgMatch) return imgMatch[1];

  return null;
}

function extractAudio(item) {
  if (item.enclosure?.type?.startsWith("audio/")) return item.enclosure.url;
  if (item.mediaContent?.$.type?.startsWith("audio/")) return item.mediaContent.$.url;
  return null;
}

// --- Deterministic UUID ---

function deterministicUUID(feedId, link) {
  const input = `${feedId}|${link}`;
  const hash = crypto.createHash("md5").update(input).digest("hex");
  return [
    hash.substring(0, 8),
    hash.substring(8, 12),
    hash.substring(12, 16),
    hash.substring(16, 20),
    hash.substring(20, 32),
  ].join("-");
}

// --- Push Notifications ---

async function notifySubscribers(feedId) {
  const subs = await query(
    `SELECT user_id FROM user_feeds WHERE feed_id = $1`,
    [feedId]
  );

  for (const sub of subs.rows) {
    const tokens = await dynamo.send(
      new QueryCommand({
        TableName: DEVICE_TOKENS_TABLE,
        KeyConditionExpression: "userId = :uid",
        ExpressionAttributeValues: { ":uid": { S: sub.user_id } },
      })
    );

    for (const item of tokens.Items || []) {
      const token = item.deviceToken?.S;
      if (!token || !PLATFORM_ARN) continue;

      try {
        await sns.send(
          new PublishCommand({
            TargetArn: PLATFORM_ARN,
            Message: JSON.stringify({
              APNS: JSON.stringify({
                aps: { "content-available": 1 },
              }),
            }),
            MessageStructure: "json",
          })
        );
      } catch (err) {
        console.warn(`Push failed for user ${sub.user_id}:`, err.message);
      }
    }
  }
}
