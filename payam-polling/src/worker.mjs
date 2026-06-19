// worker — SQS-triggered. One message per feed URL. Performs the conditional
// GET, parses the feed, dedup-inserts new items into the items table, and
// updates the registry row (etag/lastModified/lastFetchedAt + velocity tier).
//
// APNs fanout to subscribers is intentionally stubbed — depends on the
// Phase 2 device-tokens table and lands in the iOS-integration follow-up plan.

import {
  GetCommand, UpdateCommand, BatchWriteCommand,
} from '@aws-sdk/lib-dynamodb';

import { ddb, TABLES } from './lib/ddb.mjs';
import { feedIdFor, itemIdFor } from './lib/keys.mjs';
import { inferVelocityTier } from './lib/velocity.mjs';
import { parseFeed } from './lib/parser.mjs';

const FETCH_TIMEOUT_MS = 12_000;
const TTL_SECONDS = 30 * 24 * 60 * 60;
const DEAD_THRESHOLD = 8;

export async function main(event) {
  for (const record of event.Records ?? []) {
    let body;
    try {
      body = JSON.parse(record.body);
    } catch (err) {
      console.error(JSON.stringify({ event: 'worker.bad_message', err: String(err) }));
      continue;
    }
    try {
      await handleFeed(body);
    } catch (err) {
      console.error(JSON.stringify({
        event: 'worker.error',
        feedUrl: body?.feedUrl,
        receiveCount: record.attributes?.ApproximateReceiveCount,
        err: String(err),
      }));
      // Only count one failure per orchestrator-triggered message regardless of
      // how many times SQS retries it. Without this guard, a single transient
      // error (timeout, 429, 503) with a maxReceiveCount of 3 would call
      // recordFailure three times in rapid succession and dead-flag the feed
      // before any real polling problem exists.
      const isFirstDelivery = record.attributes?.ApproximateReceiveCount === '1';
      if (isFirstDelivery) {
        await recordFailure(body.feedUrl);
      }
      // Rethrow so SQS retries via the queue's redrive policy.
      throw err;
    }
  }
}

async function handleFeed({ feedUrl, etag, lastModified }) {
  const feedId = feedIdFor(feedUrl);
  const nowSec = Math.floor(Date.now() / 1000);

  const headers = {
    'User-Agent': 'Payam/2.0 (Server; polling)',
    'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*',
  };
  if (etag) headers['If-None-Match'] = etag;
  if (lastModified) headers['If-Modified-Since'] = lastModified;

  const ctrl = new AbortController();
  const tm = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  let res;
  try {
    res = await fetch(feedUrl, { headers, signal: ctrl.signal, redirect: 'follow' });
  } finally {
    clearTimeout(tm);
  }

  if (res.status === 304) {
    await bumpLastFetched(feedUrl, nowSec);
    console.log(JSON.stringify({ event: 'worker.not_modified', feedUrl }));
    return;
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }

  const xml = await res.text();
  const { feed: feedMeta, items } = await parseFeed(xml, { feedUrl });

  const newRows = items
    .filter((p) => p.title && p.link)
    .map((p) => itemRow({ feedId, parsed: p, nowSec }));

  if (newRows.length > 0) {
    await batchPutItems(newRows);
  }

  const tier = inferTierFromItems(items, nowSec);
  await ddb.send(new UpdateCommand({
    TableName: TABLES.registry,
    Key: { feedUrl },
    UpdateExpression: [
      'SET feedId = :fid',
      'lastFetchedAt = :now',
      'lastItemAt = :lastItem',
      'velocityTier = :tier',
      'etag = :etag',
      'lastModified = :lm',
      'title = if_not_exists(title, :title)',
      'description = if_not_exists(description, :desc)',
      'imageURL = if_not_exists(imageURL, :img)',
      'consecutiveFailures = :zero',
      'isDead = :false',
    ].join(', '),
    ExpressionAttributeValues: {
      ':fid': feedId,
      ':now': nowSec,
      ':lastItem': latestPublishedAt(items, nowSec),
      ':tier': tier,
      ':etag': res.headers.get('etag') ?? null,
      ':lm': res.headers.get('last-modified') ?? null,
      ':title': feedMeta.title ?? null,
      ':desc': feedMeta.description ?? null,
      ':img': feedMeta.imageURL ?? null,
      ':zero': 0,
      ':false': false,
    },
  }));

  console.log(JSON.stringify({
    event: 'worker.success',
    feedUrl, feedId, inserted: newRows.length, tier,
  }));

  // TODO(follow-up plan): fan out APNs silent pushes to subscribers
  // by querying user-feeds for this feedUrl and publishing to SNS.
}

function itemRow({ feedId, parsed, nowSec }) {
  return {
    feedId,
    link: parsed.link,
    itemId: itemIdFor(feedId, parsed.link),
    title: parsed.title,
    excerpt: parsed.excerpt ?? null,
    author: parsed.author ?? null,
    imageURL: parsed.imageURL ?? null,
    audioURL: parsed.audioURL ?? null,
    videoURL: parsed.videoURL ?? null,
    publishedAt: parsed.publishedAt ?? nowSec,
    fetchedAt: nowSec,
    ttl: nowSec + TTL_SECONDS,
  };
}

async function batchPutItems(rows) {
  // BatchWrite rejects batches with duplicate primary keys. Podcast feeds can
  // surface the same episode URL more than once per parse (e.g. NPR Hidden Brain
  // re-lists an episode). Deduplicate by itemId, keeping the most recent entry.
  const byKey = new Map();
  for (const row of rows) {
    const existing = byKey.get(row.itemId);
    if (!existing || row.publishedAt > existing.publishedAt) {
      byKey.set(row.itemId, row);
    }
  }
  const deduped = [...byKey.values()];

  for (let i = 0; i < deduped.length; i += 25) {
    const slice = deduped.slice(i, i + 25);
    const RequestItems = {
      [TABLES.items]: slice.map((Item) => ({ PutRequest: { Item } })),
    };
    let unprocessed = RequestItems;
    let attempts = 0;
    while (unprocessed && Object.keys(unprocessed).length > 0 && attempts < 5) {
      const res = await ddb.send(new BatchWriteCommand({ RequestItems: unprocessed }));
      unprocessed = res.UnprocessedItems;
      attempts++;
      if (unprocessed && Object.keys(unprocessed).length > 0) {
        await new Promise((r) => setTimeout(r, 100 * 2 ** attempts));
      }
    }
  }
}

function latestPublishedAt(items, fallback) {
  let max = fallback;
  for (const it of items) {
    if (typeof it.publishedAt === 'number' && it.publishedAt > max) max = it.publishedAt;
  }
  return max;
}

function inferTierFromItems(items, nowSec) {
  if (items.length < 2) return 'article';
  const stamps = items
    .map((i) => i.publishedAt)
    .filter((n) => typeof n === 'number');
  if (stamps.length < 2) return 'article';
  const earliest = Math.min(...stamps);
  const latest = Math.max(...stamps);
  const span = Math.max(1, latest - earliest);
  return inferVelocityTier(stamps.length, span);
}

async function bumpLastFetched(feedUrl, nowSec) {
  await ddb.send(new UpdateCommand({
    TableName: TABLES.registry,
    Key: { feedUrl },
    UpdateExpression: 'SET lastFetchedAt = :now, consecutiveFailures = :zero, isDead = :false',
    ExpressionAttributeValues: { ':now': nowSec, ':zero': 0, ':false': false },
  }));
}

async function recordFailure(feedUrl) {
  if (!feedUrl) return;
  try {
    const existing = await ddb.send(new GetCommand({
      TableName: TABLES.registry,
      Key: { feedUrl },
      ProjectionExpression: 'consecutiveFailures',
    }));
    const next = Number(existing.Item?.consecutiveFailures ?? 0) + 1;
    await ddb.send(new UpdateCommand({
      TableName: TABLES.registry,
      Key: { feedUrl },
      UpdateExpression: 'SET consecutiveFailures = :n, isDead = :dead',
      ExpressionAttributeValues: {
        ':n': next,
        ':dead': next >= DEAD_THRESHOLD,
      },
    }));
  } catch (err) {
    console.error(JSON.stringify({ event: 'worker.failure_record_error', err: String(err) }));
  }
}
