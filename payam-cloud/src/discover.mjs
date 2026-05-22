// POST /v1/discover
// Queries feed_registry for feeds matching a topic, ranked by quality.
// Accepts ephemeral topicAffinities for personalized re-ranking.
// topicAffinities are NEVER stored — used in Lambda memory only, then discarded.

import { query } from "./db.mjs";
import { requireAuth } from "./jwt.mjs";

async function handler(event) {
  const body = JSON.parse(event.body || "{}");
  const {
    query: searchQuery,
    subscribedURLs = [],
    topicAffinities = {},
    limit = 10,
    contentType,
  } = body;

  if (!searchQuery || typeof searchQuery !== "string" || searchQuery.trim().length === 0) {
    return respond(400, { error: "query is required" });
  }

  const effectiveLimit = Math.min(Math.max(1, limit), 30);
  const searchTokens = searchQuery.toLowerCase().split(/\W+/).filter(Boolean);

  if (searchTokens.length === 0) {
    return respond(400, { error: "query must contain searchable terms" });
  }

  // Query feed_registry: topic tags (GIN) + title/description (ILIKE)
  const conditions = [];
  const params = [];
  let paramIdx = 1;

  // Topic tag match (array overlap)
  params.push(searchTokens);
  conditions.push(`topic_tags && $${paramIdx++}`);

  // Title/description fuzzy match
  const ilikePatterns = searchTokens.map((t) => `%${t}%`);
  params.push(ilikePatterns);
  conditions.push(`(title ILIKE ANY($${paramIdx}) OR description ILIKE ANY($${paramIdx}))`);
  paramIdx++;

  // Optional content type filter
  if (contentType) {
    params.push(contentType);
    conditions.push(`content_type = $${paramIdx++}`);
  }

  // Fetch candidates (2x limit to allow for filtering)
  params.push(effectiveLimit * 3);

  const result = await query(
    `SELECT id, feed_url, title, description, image_url, quality_score,
            topic_tags, subscriber_count, velocity_tier, content_type
     FROM feed_registry
     WHERE is_dead = FALSE
       AND quality_score >= 0
       AND (${conditions.join(" OR ")})
       ${contentType ? `AND content_type = $${paramIdx - 1}` : ""}
     ORDER BY quality_score DESC, subscriber_count DESC
     LIMIT $${paramIdx}`,
    params
  );

  // Re-rank using ephemeral topicAffinities (privacy-safe: never stored)
  const scored = result.rows.map((feed) => {
    let affinityBoost = 0;
    const tags = feed.topic_tags || [];
    for (const tag of tags) {
      affinityBoost += topicAffinities[tag] || 0;
    }
    const normalizedBoost = tags.length > 0 ? affinityBoost / tags.length : 0;

    return {
      ...feed,
      personalizedScore: feed.quality_score * 0.6 + normalizedBoost * 0.4,
    };
  });

  scored.sort((a, b) => b.personalizedScore - a.personalizedScore);

  // Filter out already-subscribed feeds
  const subscribedSet = new Set(subscribedURLs.map((u) => u.toLowerCase()));
  const results = scored
    .filter((f) => !subscribedSet.has(f.feed_url.toLowerCase()))
    .slice(0, effectiveLimit)
    .map((f) => ({
      feedUrl: f.feed_url,
      title: f.title,
      description: f.description,
      imageUrl: f.image_url,
      qualityScore: f.quality_score,
      topicTags: f.topic_tags || [],
      subscriberCount: f.subscriber_count,
      velocityTier: f.velocity_tier,
      contentType: f.content_type,
    }));

  return respond(200, { feeds: results, total: results.length });
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

export const main = requireAuth(handler);
