-- Payam Cloud — Feed Enrichment Schema
-- Adds quality signals, topic tags, and extraction metadata
-- to support the polling → extraction → discovery flywheel.
-- All columns are feed-level data (about the content, NOT the user).

-- Feed-level quality & discovery signals
ALTER TABLE feed_registry ADD COLUMN quality_score        REAL DEFAULT 0.5;
ALTER TABLE feed_registry ADD COLUMN topic_tags           TEXT[] DEFAULT '{}';
ALTER TABLE feed_registry ADD COLUMN avg_word_count       INT DEFAULT 0;
ALTER TABLE feed_registry ADD COLUMN extraction_rate      REAL DEFAULT 0;
ALTER TABLE feed_registry ADD COLUMN content_type         TEXT DEFAULT 'article';
ALTER TABLE feed_registry ADD COLUMN consecutive_failures INT DEFAULT 0;
ALTER TABLE feed_registry ADD COLUMN last_enriched_at     TIMESTAMPTZ;

-- Per-item extraction metadata
ALTER TABLE feed_items ADD COLUMN word_count      INT;
ALTER TABLE feed_items ADD COLUMN topic_tags      TEXT[] DEFAULT '{}';
ALTER TABLE feed_items ADD COLUMN extracted_at    TIMESTAMPTZ;
ALTER TABLE feed_items ADD COLUMN extraction_tier TEXT;

-- Discovery indexes
CREATE INDEX idx_feed_registry_topics  ON feed_registry USING GIN (topic_tags);
CREATE INDEX idx_feed_registry_quality ON feed_registry (quality_score DESC) WHERE is_dead = FALSE;
