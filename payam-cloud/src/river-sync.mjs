// GET /v1/river?since={epoch}&limit={500}
// Returns feed item delta for the authenticated user.

import { query } from "./db.mjs";
import { requireAuth } from "./jwt.mjs";

async function handler(event) {
  const userId = event.auth.sub;
  const since = event.queryStringParameters?.since || "0";
  const limit = Math.min(parseInt(event.queryStringParameters?.limit || "500"), 500);

  const sinceDate = new Date(parseInt(since) * 1000);

  const result = await query(
    `SELECT fi.id, fi.feed_id, fi.title, fi.link,
            EXTRACT(EPOCH FROM fi.published_at)::bigint AS published_at,
            EXTRACT(EPOCH FROM fi.fetched_at)::bigint AS fetched_at,
            fi.excerpt, fi.image_url, fi.audio_url, fi.video_url,
            fi.author, fi.velocity_tier,
            COALESCE(uis.is_read, false) AS is_read,
            COALESCE(uis.is_bookmarked, false) AS is_bookmarked
     FROM feed_items fi
     JOIN user_feeds uf ON fi.feed_id = uf.feed_id
     LEFT JOIN user_item_state uis ON fi.id = uis.item_id AND uis.user_id = $1
     WHERE uf.user_id = $1
       AND fi.fetched_at > $2
     ORDER BY fi.published_at DESC
     LIMIT $3`,
    [userId, sinceDate, limit]
  );

  // Build source ID mapping: feed_registry.feed_url → deterministic UUID
  const feedIds = [...new Set(result.rows.map((r) => r.feed_id))];
  let feedUrlMap = {};
  if (feedIds.length > 0) {
    const placeholders = feedIds.map((_, i) => `$${i + 1}`).join(",");
    const feeds = await query(
      `SELECT id, feed_url FROM feed_registry WHERE id IN (${placeholders})`,
      feedIds
    );
    for (const f of feeds.rows) {
      feedUrlMap[f.id] = f.feed_url;
    }
  }

  const items = result.rows.map((row) => ({
    id: row.id,
    sourceID: row.feed_id,
    title: row.title,
    link: row.link,
    publishedAt: row.published_at,
    fetchedAt: row.fetched_at,
    excerpt: row.excerpt || "",
    imageURL: row.image_url,
    audioURL: row.audio_url,
    videoURL: row.video_url,
    author: row.author,
    velocityTier: row.velocity_tier || "article",
    isRead: row.is_read,
    isBookmarked: row.is_bookmarked,
  }));

  const syncToken = result.rows.length > 0
    ? String(Math.max(...result.rows.map((r) => r.fetched_at)))
    : since;

  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      items,
      syncToken,
      hasMore: result.rows.length === limit,
    }),
  };
}

export const main = requireAuth(handler, process.env.JWT_SECRET);
