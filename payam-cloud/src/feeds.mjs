// POST /v1/feeds
// Manages user feed subscriptions. Accepts added/removed feed URLs.
// Creates feed_registry entries for new URLs (picked up by next orchestrator scan).
// Atomically updates subscriber_count so pre-extraction triggers at threshold.

import { query } from "./db.mjs";
import { requireAuth } from "./jwt.mjs";
import crypto from "node:crypto";

async function handler(event) {
  const userId = event.auth.sub;
  const body = JSON.parse(event.body || "{}");
  const { added = [], removed = [] } = body;

  if (!Array.isArray(added) || !Array.isArray(removed)) {
    return respond(400, { error: "added and removed must be arrays" });
  }

  if (added.length === 0 && removed.length === 0) {
    return respond(400, { error: "At least one added or removed feed is required" });
  }

  let addedCount = 0;
  let removedCount = 0;

  // Process additions
  for (const entry of added) {
    const feedUrl = (typeof entry === "string" ? entry : entry.feedUrl)?.trim();
    const folder = (typeof entry === "object" ? entry.folder : null) || null;
    if (!feedUrl) continue;

    // Ensure feed exists in registry (upsert with lastFetchedAt=NULL so orchestrator picks it up)
    const upsertResult = await query(
      `INSERT INTO feed_registry (feed_url, velocity_tier)
       VALUES ($1, 'article')
       ON CONFLICT (feed_url) DO UPDATE SET feed_url = EXCLUDED.feed_url
       RETURNING id`,
      [feedUrl]
    );
    const feedId = upsertResult.rows[0]?.id;
    if (!feedId) continue;

    // Subscribe user (skip if already subscribed)
    const subResult = await query(
      `INSERT INTO user_feeds (user_id, feed_id, folder_name)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, feed_id) DO NOTHING
       RETURNING feed_id`,
      [userId, feedId, folder]
    );

    // Only increment subscriber_count if this is a new subscription
    if (subResult.rowCount > 0) {
      await query(
        `UPDATE feed_registry SET subscriber_count = subscriber_count + 1 WHERE id = $1`,
        [feedId]
      );
      addedCount++;
    }
  }

  // Process removals
  for (const entry of removed) {
    const feedUrl = (typeof entry === "string" ? entry : entry.feedUrl)?.trim();
    if (!feedUrl) continue;

    // Look up feed_id
    const feedResult = await query(
      `SELECT id FROM feed_registry WHERE feed_url = $1`,
      [feedUrl]
    );
    const feedId = feedResult.rows[0]?.id;
    if (!feedId) continue;

    // Remove subscription
    const delResult = await query(
      `DELETE FROM user_feeds WHERE user_id = $1 AND feed_id = $2 RETURNING feed_id`,
      [userId, feedId]
    );

    // Only decrement if subscription actually existed
    if (delResult.rowCount > 0) {
      await query(
        `UPDATE feed_registry SET subscriber_count = GREATEST(0, subscriber_count - 1) WHERE id = $1`,
        [feedId]
      );
      removedCount++;
    }
  }

  return respond(200, { added: addedCount, removed: removedCount });
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

export const main = requireAuth(handler, process.env.JWT_SECRET);
