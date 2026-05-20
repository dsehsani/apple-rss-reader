// Live feed registry queries — replaces static catalog for discovery.
// Reads from the shared payam-cloud PostgreSQL database (read-only).
// Falls back to static catalog when DB is unavailable.

import pg from "pg";

let pool = null;

function getPool() {
  if (!pool) {
    pool = new pg.Pool({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || "5432"),
      database: process.env.DB_NAME || "payam",
      user: process.env.DB_USER || "payam",
      password: process.env.DB_PASSWORD,
      max: 2,
      idleTimeoutMillis: 60_000,
      connectionTimeoutMillis: 5_000,
      ssl: { rejectUnauthorized: false },
    });
  }
  return pool;
}

async function dbQuery(text, params) {
  const client = await getPool().connect();
  try {
    return await client.query(text, params);
  } finally {
    client.release();
  }
}

/**
 * Search the live feed_registry for feeds matching a topic.
 * Returns candidates ranked by quality_score × subscriber_count.
 *
 * @param {string} topic — the search topic
 * @param {object} [options]
 * @param {number} [options.limit=10]
 * @returns {Array<{name, feedURL, description, category, qualityScore, subscriberCount}>}
 */
export async function candidatesFromRegistry(topic, { limit = 10 } = {}) {
  if (!process.env.DB_HOST) return [];

  const tokens = topic.toLowerCase().split(/\W+/).filter(Boolean);
  if (tokens.length === 0) return [];

  const ilikePatterns = tokens.map((t) => `%${t}%`);

  try {
    const result = await dbQuery(
      `SELECT feed_url, title, description, quality_score, topic_tags,
              subscriber_count, content_type, image_url
       FROM feed_registry
       WHERE is_dead = FALSE
         AND quality_score >= 0.3
         AND (
           topic_tags && $1
           OR title ILIKE ANY($2)
           OR description ILIKE ANY($2)
         )
       ORDER BY quality_score DESC, subscriber_count DESC
       LIMIT $3`,
      [tokens, ilikePatterns, limit * 2]
    );

    return result.rows.map((r) => ({
      name: r.title || r.feed_url,
      feedURL: r.feed_url,
      description: r.description || "",
      category: (r.topic_tags || [])[0] || "General",
      qualityScore: r.quality_score,
      subscriberCount: r.subscriber_count,
      contentType: r.content_type,
    }));
  } catch (err) {
    console.warn("Registry query failed, will fall back to static catalog:", err.message);
    return [];
  }
}
