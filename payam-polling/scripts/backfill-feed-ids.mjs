#!/usr/bin/env node
// One-shot migration that repairs the May-19 feedId truncation residue.
//
// Why: keys.mjs originally truncated sha256(feedUrl) to 32 hex chars; the
// 4d6fa2f fix kept the full 64. Existing userFeeds + registry rows still hold
// the old 32-char feedId, so river.mjs queries items under the wrong key and
// the iOS client sees stale feeds.
//
// Usage:
//   node scripts/backfill-feed-ids.mjs [--stage <stage>] [--dry-run] [--cleanup-items]
//
// --stage defaults to 'dev' (matches serverless.yml). Set AWS_REGION to override us-west-2.

import { ScanCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';

import { feedIdFor } from '../src/lib/keys.mjs';

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has('--dry-run');
const CLEANUP_ITEMS = args.has('--cleanup-items');
const stage = readFlag('--stage') ?? 'dev';

process.env.REGISTRY_TABLE ??= `payam-polling-${stage}-feed-registry`;
process.env.ITEMS_TABLE ??= `payam-polling-${stage}-feed-items`;
process.env.USER_FEEDS_TABLE ??= `payam-polling-${stage}-user-feeds`;
process.env.USER_ITEM_STATE_TABLE ??= `payam-polling-${stage}-user-item-state`;

const { ddb, TABLES } = await import('../src/lib/ddb.mjs');

function readFlag(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

async function* scanAll(TableName) {
  let ExclusiveStartKey;
  do {
    const res = await ddb.send(new ScanCommand({ TableName, ExclusiveStartKey }));
    for (const item of res.Items ?? []) yield item;
    ExclusiveStartKey = res.LastEvaluatedKey;
  } while (ExclusiveStartKey);
}

async function backfillUserFeeds() {
  const summary = { total: 0, updated: 0, alreadyCorrect: 0, skipped: 0, failed: [] };
  for await (const row of scanAll(TABLES.userFeeds)) {
    summary.total++;
    if (!row.feedUrl) { summary.skipped++; continue; }
    const expected = feedIdFor(row.feedUrl);
    if (row.feedId === expected) { summary.alreadyCorrect++; continue; }

    if (DRY_RUN) { summary.updated++; continue; }
    try {
      await ddb.send(new UpdateCommand({
        TableName: TABLES.userFeeds,
        Key: { userId: row.userId, feedUrl: row.feedUrl },
        UpdateExpression: 'SET feedId = :new',
        ExpressionAttributeValues: { ':new': expected },
      }));
      summary.updated++;
    } catch (err) {
      summary.failed.push({ key: { userId: row.userId, feedUrl: row.feedUrl }, err: String(err) });
    }
  }
  return summary;
}

async function backfillRegistry() {
  const summary = { total: 0, updated: 0, alreadyCorrect: 0, skipped: 0, failed: [] };
  for await (const row of scanAll(TABLES.registry)) {
    summary.total++;
    if (!row.feedUrl) { summary.skipped++; continue; }
    const expected = feedIdFor(row.feedUrl);
    if (row.feedId === expected) { summary.alreadyCorrect++; continue; }

    if (DRY_RUN) { summary.updated++; continue; }
    try {
      await ddb.send(new UpdateCommand({
        TableName: TABLES.registry,
        Key: { feedUrl: row.feedUrl },
        UpdateExpression: 'SET feedId = :new',
        ExpressionAttributeValues: { ':new': expected },
      }));
      summary.updated++;
    } catch (err) {
      summary.failed.push({ key: { feedUrl: row.feedUrl }, err: String(err) });
    }
  }
  return summary;
}

async function cleanupOrphanItems() {
  const summary = { total: 0, deleted: 0, kept: 0, failed: [] };
  for await (const row of scanAll(TABLES.items)) {
    summary.total++;
    if (typeof row.feedId === 'string' && row.feedId.length === 64) { summary.kept++; continue; }
    if (DRY_RUN) { summary.deleted++; continue; }
    try {
      await ddb.send(new DeleteCommand({
        TableName: TABLES.items,
        Key: { feedId: row.feedId, link: row.link },
      }));
      summary.deleted++;
    } catch (err) {
      summary.failed.push({ key: { feedId: row.feedId, link: row.link }, err: String(err) });
    }
  }
  return summary;
}

function printSummary(label, s) {
  console.log(`\n[${label}]`);
  for (const [k, v] of Object.entries(s)) {
    if (k === 'failed') {
      console.log(`  ${k}: ${v.length}`);
      for (const f of v.slice(0, 5)) console.log(`    - ${JSON.stringify(f)}`);
      if (v.length > 5) console.log(`    ... ${v.length - 5} more`);
    } else {
      console.log(`  ${k}: ${v}`);
    }
  }
}

console.log(`Stage: ${stage}  dryRun=${DRY_RUN}  cleanupItems=${CLEANUP_ITEMS}`);
console.log(`Tables: ${JSON.stringify(TABLES, null, 2)}`);

const userFeeds = await backfillUserFeeds();
printSummary('userFeeds', userFeeds);

const registry = await backfillRegistry();
printSummary('registry', registry);

let items = null;
if (CLEANUP_ITEMS) {
  items = await cleanupOrphanItems();
  printSummary('items (orphans)', items);
}

const failureCount = userFeeds.failed.length + registry.failed.length + (items?.failed.length ?? 0);
process.exit(failureCount === 0 ? 0 : 1);
