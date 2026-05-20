// EventBridge (every 1 hour) → This Lambda
// Recomputes feed-level quality scores, topic tags, and extraction rates
// from item-level data. These aggregate signals power the discovery endpoint.
// All data is feed-level (about the content, NOT the user).

import { query } from "./db.mjs";

export async function main() {
  // Recompute quality signals for all active feeds with items in the last 30 days
  const result = await query(`
    UPDATE feed_registry fr SET
      quality_score = sub.score,
      topic_tags = sub.tags,
      avg_word_count = sub.avg_wc,
      extraction_rate = sub.ext_rate,
      last_enriched_at = NOW()
    FROM (
      SELECT
        fi.feed_id,
        -- Quality: extraction success × content depth × recency
        ROUND((
          0.4 * COALESCE(fi.ext_rate, 0) +
          0.3 * LEAST(1.0, COALESCE(fi.avg_wc, 0) / 800.0) +
          0.3 * CASE
            WHEN fr2.last_item_at > NOW() - INTERVAL '7 days' THEN 1.0
            WHEN fr2.last_item_at > NOW() - INTERVAL '30 days' THEN 0.5
            ELSE 0.2
          END
        )::numeric, 3) AS score,
        COALESCE(fi.tags, '{}') AS tags,
        COALESCE(fi.avg_wc, 0)::int AS avg_wc,
        ROUND(COALESCE(fi.ext_rate, 0)::numeric, 3) AS ext_rate
      FROM feed_registry fr2
      JOIN LATERAL (
        SELECT
          feed_id,
          AVG(word_count) FILTER (WHERE word_count IS NOT NULL) AS avg_wc,
          COUNT(*) FILTER (WHERE extracted_at IS NOT NULL)::real
            / GREATEST(COUNT(*), 1) AS ext_rate,
          -- Aggregate item-level topic tags into feed-level array (deduplicated)
          (
            SELECT COALESCE(array_agg(DISTINCT t), '{}')
            FROM feed_items fi2, unnest(fi2.topic_tags) t
            WHERE fi2.feed_id = fr2.id
              AND fi2.published_at > NOW() - INTERVAL '30 days'
              AND fi2.topic_tags IS NOT NULL
              AND array_length(fi2.topic_tags, 1) > 0
          ) AS tags
        FROM feed_items
        WHERE feed_id = fr2.id
          AND published_at > NOW() - INTERVAL '30 days'
        GROUP BY feed_id
      ) fi ON TRUE
      WHERE fr2.is_dead = FALSE
    ) sub
    WHERE fr.id = sub.feed_id
  `);

  const updated = result.rowCount ?? 0;
  console.log(`Enriched ${updated} feeds with quality scores and topic tags`);

  // Also detect and mark content_type for feeds that are primarily podcasts
  await query(`
    UPDATE feed_registry SET content_type = 'podcast'
    WHERE id IN (
      SELECT feed_id FROM feed_items
      WHERE published_at > NOW() - INTERVAL '30 days'
        AND audio_url IS NOT NULL
      GROUP BY feed_id
      HAVING COUNT(*) FILTER (WHERE audio_url IS NOT NULL)::real / COUNT(*) > 0.7
    )
    AND content_type != 'podcast'
  `);
}
