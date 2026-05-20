// Tests for the feed orchestrator's tier-aware polling logic.
// Run: node --test tests/unit/orchestrator.test.mjs

import { describe, it } from "node:test";
import assert from "node:assert/strict";

// --- Extracted from feed-orchestrator.mjs for unit testing ---

const POLL_INTERVALS = {
  breaking:  5 * 60,
  news:      15 * 60,
  article:   60 * 60,
  essay:     6 * 60 * 60,
  evergreen: 24 * 60 * 60,
};

const DEAD_RETRY_SECONDS = 24 * 60 * 60;

function isDueForPoll(feed, nowSec) {
  const lastFetched = feed.last_fetched_epoch ?? 0;
  if (feed.is_dead) {
    return nowSec - lastFetched > DEAD_RETRY_SECONDS;
  }
  const interval = POLL_INTERVALS[feed.velocity_tier] ?? POLL_INTERVALS.article;
  return nowSec - lastFetched >= interval;
}

// --- End extracted ---

describe("Tier-Aware Polling", () => {
  const NOW = Date.now() / 1000;

  it("polls breaking feeds every 5 minutes", () => {
    const feed = { velocity_tier: "breaking", last_fetched_epoch: NOW - 301, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW), "Should be due after 5min+1s");

    const recent = { velocity_tier: "breaking", last_fetched_epoch: NOW - 200, is_dead: false };
    assert.ok(!isDueForPoll(recent, NOW), "Should NOT be due after 3min 20s");
  });

  it("polls news feeds every 15 minutes", () => {
    const feed = { velocity_tier: "news", last_fetched_epoch: NOW - 901, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));

    const recent = { velocity_tier: "news", last_fetched_epoch: NOW - 600, is_dead: false };
    assert.ok(!isDueForPoll(recent, NOW));
  });

  it("polls article feeds every 1 hour", () => {
    const feed = { velocity_tier: "article", last_fetched_epoch: NOW - 3601, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));

    const recent = { velocity_tier: "article", last_fetched_epoch: NOW - 1800, is_dead: false };
    assert.ok(!isDueForPoll(recent, NOW));
  });

  it("polls essay feeds every 6 hours", () => {
    const feed = { velocity_tier: "essay", last_fetched_epoch: NOW - (6 * 3600 + 1), is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));

    const recent = { velocity_tier: "essay", last_fetched_epoch: NOW - 3600, is_dead: false };
    assert.ok(!isDueForPoll(recent, NOW));
  });

  it("polls evergreen feeds every 24 hours", () => {
    const feed = { velocity_tier: "evergreen", last_fetched_epoch: NOW - (24 * 3600 + 1), is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));

    const recent = { velocity_tier: "evergreen", last_fetched_epoch: NOW - 12 * 3600, is_dead: false };
    assert.ok(!isDueForPoll(recent, NOW));
  });

  it("defaults unknown tiers to article (1 hour)", () => {
    const feed = { velocity_tier: "unknown_tier", last_fetched_epoch: NOW - 3601, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));
  });

  it("always polls feeds never fetched", () => {
    const feed = { velocity_tier: "evergreen", last_fetched_epoch: 0, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));
  });

  it("always polls feeds with null last_fetched_epoch", () => {
    const feed = { velocity_tier: "article", last_fetched_epoch: null, is_dead: false };
    assert.ok(isDueForPoll(feed, NOW));
  });
});

describe("Dead Feed Retry", () => {
  const NOW = Date.now() / 1000;

  it("retries dead feeds after 24 hours", () => {
    const feed = { velocity_tier: "article", last_fetched_epoch: NOW - (24 * 3600 + 1), is_dead: true };
    assert.ok(isDueForPoll(feed, NOW), "Dead feed should retry after 24h");
  });

  it("does NOT retry dead feeds before 24 hours", () => {
    const feed = { velocity_tier: "article", last_fetched_epoch: NOW - 12 * 3600, is_dead: true };
    assert.ok(!isDueForPoll(feed, NOW), "Dead feed should wait 24h");
  });

  it("ignores velocity tier for dead feeds", () => {
    // Even a breaking feed that's dead should wait 24h
    const feed = { velocity_tier: "breaking", last_fetched_epoch: NOW - 600, is_dead: true };
    assert.ok(!isDueForPoll(feed, NOW));
  });
});

describe("Velocity Tier Inference", () => {
  // Extracted from feed-worker.mjs
  function inferVelocityTier(itemsCount, daySpanSeconds) {
    const days = Math.max(1, daySpanSeconds / 86400);
    const perDay = itemsCount / days;
    if (perDay >= 50) return "breaking";
    if (perDay >= 10) return "news";
    if (perDay >= 1) return "article";
    if (perDay >= 0.15) return "essay";
    return "evergreen";
  }

  it("classifies high-frequency feeds as breaking", () => {
    assert.equal(inferVelocityTier(100, 86400), "breaking"); // 100/day
  });

  it("classifies moderate feeds as news", () => {
    assert.equal(inferVelocityTier(15, 86400), "news"); // 15/day
  });

  it("classifies daily feeds as article", () => {
    assert.equal(inferVelocityTier(3, 86400 * 2), "article"); // 1.5/day
  });

  it("classifies weekly feeds as essay", () => {
    assert.equal(inferVelocityTier(1, 86400 * 5), "essay"); // 0.2/day
  });

  it("classifies monthly feeds as evergreen", () => {
    assert.equal(inferVelocityTier(1, 86400 * 30), "evergreen"); // 0.03/day
  });

  it("handles zero span (same day)", () => {
    // daySpanSeconds = 0 → clamped to 1 day
    assert.equal(inferVelocityTier(5, 0), "article"); // 5 items in <=1 day
  });
});
