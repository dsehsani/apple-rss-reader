// GET /v1/river?since={epoch}&limit={500}
// Returns feed item delta for the authenticated user.
// Response includes serverTime (epoch seconds) so the iOS client tracks
// sync position using the server's clock, not the device clock.

import { query } from "./db.mjs";
import { requireAuth } from "./jwt.mjs";

async function handler(event) {
  const userId = event.auth.sub;
  const since = event.queryStringParameters?.since || "0";
  const rawLimit = parseInt(event.queryStringParameters?.limit || "500");
  const limit = (!rawLimit || rawLimit < 1) ? 500 : Math.min(rawLimit, 500);

  const sinceDate = new Date(parseInt(since) * 1000);

  const result = await query(
    `SELECT fi.id, fi.feed_id, fr.feed_url, fi.title, fi.link,
            EXTRACT(EPOCH FROM fi.published_at)::bigint AS published_at,
            EXTRACT(EPOCH FROM fi.fetched_at)::bigint AS fetched_at,
            fi.excerpt, fi.image_url, fi.audio_url, fi.video_url,
            fi.author, fi.velocity_tier,
            COALESCE(uis.is_read, false) AS is_read,
            COALESCE(uis.is_bookmarked, false) AS is_bookmarked
     FROM feed_items fi
     JOIN feed_registry fr ON fi.feed_id = fr.id
     JOIN user_feeds uf ON fi.feed_id = uf.feed_id
     LEFT JOIN user_item_state uis ON fi.id = uis.item_id AND uis.user_id = $1
     WHERE uf.user_id = $1
       AND fi.fetched_at > $2
     ORDER BY fi.published_at DESC
     LIMIT $3`,
    [userId, sinceDate, limit]
  );

  // Map rows to the shape CloudFeedSyncService.RiverItemRow expects:
  //   feedId, itemId, link, title, excerpt, author, imageURL, audioURL, videoURL, publishedAt, fetchedAt
  const items = result.rows.map((row) => ({
    feedId: row.feed_id,
    feedURL: row.feed_url,
    itemId: row.id,
    title: row.title,
    link: row.link,
    publishedAt: Number(row.published_at),
    fetchedAt: Number(row.fetched_at),
    excerpt: row.excerpt || "",
    imageURL: row.image_url,
    audioURL: row.audio_url,
    videoURL: row.video_url,
    author: row.author,
    velocityTier: row.velocity_tier || "article",
    isRead: row.is_read,
    isBookmarked: row.is_bookmarked,
  }));

  // Server time in epoch seconds — the iOS client stores this and passes it
  // as `since` on the next sync, avoiding device clock drift issues.
  const serverTime = Math.floor(Date.now() / 1000);

  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      items,
      serverTime,
      hasMore: result.rows.length === limit,
    }),
  };
}

export const main = requireAuth(handler);
