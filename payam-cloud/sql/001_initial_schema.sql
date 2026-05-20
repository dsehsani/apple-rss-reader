-- Payam Cloud — Initial PostgreSQL Schema
-- Target: RDS t4g.micro (PostgreSQL 16)

-- Shared feed registry. One row per unique feed URL across all users.
CREATE TABLE feed_registry (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feed_url        TEXT UNIQUE NOT NULL,
    title           TEXT,
    description     TEXT,
    image_url       TEXT,
    etag            TEXT,
    last_modified   TEXT,
    last_fetched_at TIMESTAMPTZ,
    last_item_at    TIMESTAMPTZ,
    subscriber_count INT DEFAULT 0,
    velocity_tier   TEXT NOT NULL DEFAULT 'article',
    is_dead         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_feed_registry_due
    ON feed_registry (last_fetched_at)
    WHERE is_dead = FALSE;

-- Shared article store. One row per article, not per user.
CREATE TABLE feed_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feed_id         UUID NOT NULL REFERENCES feed_registry(id),
    title           TEXT NOT NULL,
    link            TEXT NOT NULL,
    published_at    TIMESTAMPTZ NOT NULL,
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    content_hash    TEXT,
    excerpt         TEXT,
    image_url       TEXT,
    audio_url       TEXT,
    video_url       TEXT,
    author          TEXT,
    velocity_tier   TEXT NOT NULL DEFAULT 'article',
    UNIQUE (feed_id, link)
);

CREATE INDEX idx_feed_items_feed_published
    ON feed_items (feed_id, published_at DESC);

CREATE INDEX idx_feed_items_fetched
    ON feed_items (fetched_at DESC);

-- Per-user feed subscriptions.
CREATE TABLE user_feeds (
    user_id         TEXT NOT NULL,
    feed_id         UUID NOT NULL REFERENCES feed_registry(id),
    folder_name     TEXT,
    added_at        TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, feed_id)
);

CREATE INDEX idx_user_feeds_user
    ON user_feeds (user_id);

-- Per-user article read/bookmark state (premium only).
CREATE TABLE user_item_state (
    user_id         TEXT NOT NULL,
    item_id         UUID NOT NULL REFERENCES feed_items(id),
    is_read         BOOLEAN DEFAULT FALSE,
    is_bookmarked   BOOLEAN DEFAULT FALSE,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, item_id)
);

-- 30-day cleanup: DELETE FROM feed_items WHERE fetched_at < NOW() - INTERVAL '30 days';
