// Velocity tiers and polling intervals — mirror VelocityTier on-device.
// Keep both sides in sync; changes here must land in the iOS client too.

export const TIERS = ['breaking', 'news', 'article', 'essay', 'evergreen'];

const POLL_INTERVAL_SECONDS = {
  breaking: 5 * 60,
  news: 15 * 60,
  article: 60 * 60,
  essay: 6 * 60 * 60,
  evergreen: 24 * 60 * 60,
};

const DEAD_RETRY_SECONDS = 24 * 60 * 60;

export function pollingIntervalSeconds(tier) {
  return POLL_INTERVAL_SECONDS[tier] ?? POLL_INTERVAL_SECONDS.article;
}

export function isDueForPoll(row, nowSec) {
  const last = Number(row.lastFetchedAt ?? 0);
  if (row.isDead) {
    return nowSec - last > DEAD_RETRY_SECONDS;
  }
  return nowSec - last >= pollingIntervalSeconds(row.velocityTier ?? 'article');
}

// Re-infer velocity from observed publish rate. Matches the buckets used by
// FeedIngestService.inferVelocityTier on-device.
export function inferVelocityTier(itemsCount, daySpanSeconds) {
  const days = Math.max(1, daySpanSeconds / 86400);
  const perDay = itemsCount / days;
  if (perDay >= 50) return 'breaking';
  if (perDay >= 10) return 'news';
  if (perDay >= 1) return 'article';
  if (perDay >= 0.15) return 'essay';
  return 'evergreen';
}
