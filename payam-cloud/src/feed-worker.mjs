// SQS → This Lambda (1 per feed URL)
// Fetches a single feed with conditional GET, diffs against existing items,
// inserts new items, and notifies subscribers via APNs.

import { query } from "./db.mjs";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";
import crypto from "node:crypto";

const sns = new SNSClient({});
const dynamo = new DynamoDBClient({});
const PLATFORM_ARN = process.env.SNS_PLATFORM_ARN;
const DEVICE_TOKENS_TABLE = process.env.DEVICE_TOKENS_TABLE || "payam-device-tokens";

export async function main(event) {
  for (const record of event.Records) {
    const msg = JSON.parse(record.body);
    await processFeed(msg);
  }
}

async function processFeed({ feedId, feedUrl, etag, lastModified, velocityTier }) {
  try {
    // Conditional GET
    const headers = {};
    if (etag) headers["If-None-Match"] = etag;
    if (lastModified) headers["If-Modified-Since"] = lastModified;

    const response = await fetch(feedUrl, {
      headers: {
        ...headers,
        "User-Agent": "Payam/1.0 RSS Reader (https://payam.app)",
        Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
      },
      signal: AbortSignal.timeout(15_000),
    });

    // Update last_fetched_at regardless
    await query(
      `UPDATE feed_registry SET last_fetched_at = NOW() WHERE id = $1`,
      [feedId]
    );

    if (response.status === 304) {
      return; // No new content
    }

    if (!response.ok) {
      // Track failures for dead feed detection
      console.warn(`Feed ${feedUrl} returned ${response.status}`);
      return;
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

    // Parse feed items
    const items = parseFeedXML(xml, feedId, velocityTier);
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

    // Notify subscribers
    await notifySubscribers(feedId);
  } catch (err) {
    console.error(`Error processing feed ${feedUrl}:`, err.message);
  }
}

// Minimal RSS/Atom parser — extracts title, link, pubDate, description
function parseFeedXML(xml, feedId, velocityTier) {
  const items = [];

  // Match <item> (RSS) or <entry> (Atom) blocks
  const itemRegex = /<(?:item|entry)[\s>]([\s\S]*?)<\/(?:item|entry)>/gi;
  let match;

  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];

    const title = extractTag(block, "title") || "";
    if (!title.trim()) continue;

    const link = extractLink(block) || "";
    if (!link.trim()) continue;

    const pubDate = extractTag(block, "pubDate") || extractTag(block, "published") || extractTag(block, "updated");
    const description = extractTag(block, "description") || extractTag(block, "summary") || extractTag(block, "content");
    const author = extractTag(block, "author") || extractTag(block, "dc:creator");
    const imageUrl = extractImageFromEnclosure(block) || extractImageFromContent(block);
    const audioUrl = extractAudioEnclosure(block);

    // Deterministic UUID from feedId + link (matches client FNV-1a scheme)
    const id = deterministicUUID(feedId, link);

    items.push({
      id,
      title: stripHTML(title).trim(),
      link: link.trim(),
      publishedAt: pubDate ? new Date(pubDate) : new Date(),
      excerpt: description ? stripHTML(description).substring(0, 500).trim() : "",
      imageUrl,
      audioUrl,
      videoUrl: null,
      author: author ? stripHTML(author).trim() : null,
    });
  }

  return items;
}

function extractTag(block, tag) {
  // Handle CDATA
  const cdataRegex = new RegExp(`<${tag}[^>]*><!\\[CDATA\\[([\\s\\S]*?)\\]\\]><\\/${tag}>`, "i");
  const cdataMatch = block.match(cdataRegex);
  if (cdataMatch) return cdataMatch[1];

  const regex = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i");
  const match = block.match(regex);
  return match ? match[1] : null;
}

function extractLink(block) {
  // RSS: <link>url</link>
  const rssLink = extractTag(block, "link");
  if (rssLink && rssLink.trim().startsWith("http")) return rssLink.trim();

  // Atom: <link href="url" />
  const atomMatch = block.match(/<link[^>]*href=["']([^"']+)["'][^>]*\/?>/i);
  if (atomMatch) return atomMatch[1];

  // Fallback: <guid>url</guid>
  const guid = extractTag(block, "guid");
  if (guid && guid.trim().startsWith("http")) return guid.trim();

  return null;
}

function extractImageFromEnclosure(block) {
  const match = block.match(/<enclosure[^>]*type=["']image\/[^"']*["'][^>]*url=["']([^"']+)["']/i);
  if (match) return match[1];
  const match2 = block.match(/<enclosure[^>]*url=["']([^"']+)["'][^>]*type=["']image\//i);
  return match2 ? match2[1] : null;
}

function extractImageFromContent(block) {
  const match = block.match(/<img[^>]*src=["']([^"']+)["']/i);
  return match ? match[1] : null;
}

function extractAudioEnclosure(block) {
  const match = block.match(/<enclosure[^>]*type=["']audio\/[^"']*["'][^>]*url=["']([^"']+)["']/i);
  if (match) return match[1];
  const match2 = block.match(/<enclosure[^>]*url=["']([^"']+)["'][^>]*type=["']audio\//i);
  return match2 ? match2[1] : null;
}

function stripHTML(str) {
  return str.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}

// Deterministic UUID v5-style from feedId + link (must match client's FNV-1a scheme)
function deterministicUUID(feedId, link) {
  const input = `${feedId}|${link}`;
  const hash = crypto.createHash("md5").update(input).digest("hex");
  // Format as UUID
  return [
    hash.substring(0, 8),
    hash.substring(8, 12),
    hash.substring(12, 16),
    hash.substring(16, 20),
    hash.substring(20, 32),
  ].join("-");
}

async function notifySubscribers(feedId) {
  // Get all users subscribed to this feed
  const subs = await query(
    `SELECT user_id FROM user_feeds WHERE feed_id = $1`,
    [feedId]
  );

  for (const sub of subs.rows) {
    // Get device tokens for this user
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
