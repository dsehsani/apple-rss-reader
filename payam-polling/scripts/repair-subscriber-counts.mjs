#!/usr/bin/env node
// Repairs subscriberCount on payam-feed-registry rows that drifted to <= 0 due
// to the non-atomic subscribe/unsubscribe bug. For each affected registry row,
// counts the actual rows in payam-user-feeds and writes the correct value.
//
// Usage:
//   node scripts/repair-subscriber-counts.mjs [--stage <stage>] [--dry-run]
//
// --stage defaults to 'dev' (matches serverless.yml). Set AWS_REGION to override us-west-2.

import { ScanCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has('--dry-run');
const stage = readFlag('--stage') ?? 'dev';

process.env.REGISTRY_TABLE   ??= `payam-polling-${stage}-feed-registry`;
process.env.USER_FEEDS_TABLE ??= `payam-polling-${stage}-user-feeds`;
process.env.AWS_REGION       ??= 'us-west-2';

const { ddb, TABLES } = await import('../src/lib/ddb.mjs');

function readFlag(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

// Yields every registry row where subscriberCount <= 0.
async function* corruptedFeeds() {
  let ExclusiveStartKey;
  do {
    const res = await ddb.send(new ScanCommand({
      TableName: TABLES.registry,
      FilterExpression: 'subscriberCount <= :zero',
      ExpressionAttributeValues: { ':zero': 0 },
      ExclusiveStartKey,
    }));
    for (const item of res.Items ?? []) yield item;
    ExclusiveStartKey = res.LastEvaluatedKey;
  } while (ExclusiveStartKey);
}

// Counts rows in payam-user-feeds for a given feedUrl. feedUrl is the sort key
// so a targeted Query isn't possible without a GSI; a filtered Scan is fine for
// a one-off repair. Select: COUNT avoids fetching item data.
async function countActualSubscribers(feedUrl) {
  let count = 0;
  let ExclusiveStartKey;
  do {
    const res = await ddb.send(new ScanCommand({
      TableName: TABLES.userFeeds,
      FilterExpression: 'feedUrl = :url',
      ExpressionAttributeValues: { ':url': feedUrl },
      Select: 'COUNT',
      ExclusiveStartKey,
    }));
    count += res.Count ?? 0;
    ExclusiveStartKey = res.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return count;
}

console.log(`Stage: ${stage}  dryRun=${DRY_RUN}`);
console.log(`Registry:  ${TABLES.registry}`);
console.log(`UserFeeds: ${TABLES.userFeeds}\n`);

const summary = { scanned: 0, restored: 0, zeroed: 0, alreadyCorrect: 0, failed: [] };

for await (const feed of corruptedFeeds()) {
  summary.scanned++;
  const { feedUrl, subscriberCount: current } = feed;

  let actual;
  try {
    actual = await countActualSubscribers(feedUrl);
  } catch (err) {
    console.error(`  ERROR  counting ${feedUrl}: ${err}`);
    summary.failed.push({ feedUrl, err: String(err) });
    continue;
  }

  if (actual === current) {
    // Count is 0 and there are genuinely 0 subscribers — nothing to fix.
    summary.alreadyCorrect++;
    console.log(`  SKIP   [${current} → ${actual}]  ${feedUrl}`);
    continue;
  }

  const tag = actual > 0 ? 'restored' : 'zeroed';
  console.log(`  ${DRY_RUN ? 'DRY-RUN' : 'FIX    '} [${current} → ${actual}]  ${feedUrl}`);

  if (!DRY_RUN) {
    try {
      await ddb.send(new UpdateCommand({
        TableName: TABLES.registry,
        Key: { feedUrl },
        UpdateExpression: 'SET subscriberCount = :actual',
        ExpressionAttributeValues: { ':actual': actual },
      }));
    } catch (err) {
      console.error(`  ERROR  updating ${feedUrl}: ${err}`);
      summary.failed.push({ feedUrl, err: String(err) });
      continue;
    }
  }

  summary[tag]++;
}

function printSummary(s) {
  console.log('\n[summary]');
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

printSummary(summary);
process.exit(summary.failed.length === 0 ? 0 : 1);
