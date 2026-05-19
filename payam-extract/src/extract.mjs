// extract — GET /v1/extractions/{urlHash}?url={encodedUrl}
//
// Synchronous extraction cache. On HIT, returns a presigned S3 URL to the
// previously-extracted JSON. On MISS, fetches the page, runs jsdom +
// @mozilla/readability inline, writes the result to S3, indexes it in
// DynamoDB with a 72-hour TTL, then returns the same presigned-URL shape.
//
// JS-rendered pages fail the readability quality gate (length < 500 chars
// or empty title). For those, we return 422 — the iOS client is expected to
// fall back to its existing on-device WKWebView extractor.

import { createHash } from 'node:crypto';

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
import { S3Client, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import { JSDOM } from 'jsdom';
import { Readability } from '@mozilla/readability';

const region = process.env.AWS_REGION ?? 'us-west-2';
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({ region });

const INDEX_TABLE = process.env.EXTRACTION_INDEX_TABLE;
const BUCKET = process.env.EXTRACTIONS_BUCKET;
const PRESIGN_TTL = Number(process.env.PRESIGN_TTL_SECONDS ?? 600);

const FETCH_TIMEOUT_MS = 10_000;
const MAX_BODY_BYTES = 5 * 1024 * 1024;
const MIN_EXTRACT_LENGTH = 500;
const CACHE_TTL_SECONDS = 72 * 60 * 60;

export async function main(event) {
  const urlHash = event.pathParameters?.urlHash;
  const url = event.queryStringParameters?.url;
  if (!urlHash || !url) {
    return resp(400, { error: 'urlHash path param and url query param required' });
  }

  const expected = sha256Hex(url);
  if (urlHash !== expected) {
    return resp(400, { error: 'urlHash does not match sha256(url)' });
  }

  // Cache lookup.
  try {
    const got = await ddb.send(new GetCommand({
      TableName: INDEX_TABLE,
      Key: { urlHash },
    }));
    if (got.Item?.s3Key) {
      const contentUrl = await presign(got.Item.s3Key);
      return resp(200, {
        status: 'hit',
        contentUrl,
        cachedAt: got.Item.cachedAt,
      });
    }
  } catch (err) {
    console.error(JSON.stringify({ event: 'extract.index_get_error', err: String(err) }));
    // Fall through to fresh extraction — better to do extra work than 500.
  }

  // Cache miss → extract.
  let html;
  try {
    html = await fetchHtml(url);
  } catch (err) {
    console.warn(JSON.stringify({ event: 'extract.fetch_failed', url, err: String(err) }));
    return resp(502, { status: 'fetch_failed', error: String(err) });
  }

  let parsed;
  try {
    const dom = new JSDOM(html, { url });
    parsed = new Readability(dom.window.document).parse();
  } catch (err) {
    console.warn(JSON.stringify({ event: 'extract.readability_threw', url, err: String(err) }));
    return resp(422, { status: 'not_extractable', reason: 'parse_error' });
  }

  if (!parsed?.title || !parsed?.content || (parsed?.length ?? 0) < MIN_EXTRACT_LENGTH) {
    return resp(422, {
      status: 'not_extractable',
      reason: 'quality_gate',
      lengthBytes: parsed?.length ?? 0,
    });
  }

  const heroImageURL = extractHeroImage(html, url);
  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    title: parsed.title,
    byline: parsed.byline ?? null,
    content: parsed.content,
    excerpt: parsed.excerpt ?? null,
    lang: parsed.lang ?? null,
    heroImageURL,
    sourceURL: url,
    extractedAt: nowSec,
  };

  const s3Key = `extractions/${urlHash}.json`;
  try {
    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: s3Key,
      Body: JSON.stringify(payload),
      ContentType: 'application/json',
      CacheControl: `max-age=${CACHE_TTL_SECONDS}`,
    }));
    await ddb.send(new PutCommand({
      TableName: INDEX_TABLE,
      Item: {
        urlHash,
        s3Key,
        cachedAt: nowSec,
        extractedHost: safeHost(url),
        ttl: nowSec + CACHE_TTL_SECONDS,
      },
    }));
  } catch (err) {
    console.error(JSON.stringify({ event: 'extract.persist_failed', err: String(err) }));
    return resp(500, { status: 'persist_failed' });
  }

  const contentUrl = await presign(s3Key);
  return resp(200, {
    status: 'miss-extracted',
    contentUrl,
    cachedAt: nowSec,
  });
}

async function fetchHtml(url) {
  const ctrl = new AbortController();
  const tm = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      redirect: 'follow',
      headers: {
        'User-Agent': 'Payam/2.0 ExtractBot (+https://payam.app/bot)',
        'Accept': 'text/html,application/xhtml+xml',
      },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const contentType = res.headers.get('content-type') ?? '';
    if (!contentType.includes('html') && !contentType.includes('xml')) {
      throw new Error(`unexpected content-type: ${contentType}`);
    }
    const reader = res.body.getReader();
    const chunks = [];
    let total = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        reader.cancel();
        throw new Error('response exceeds 5MB cap');
      }
      chunks.push(value);
    }
    return Buffer.concat(chunks).toString('utf8');
  } finally {
    clearTimeout(tm);
  }
}

function extractHeroImage(html, baseUrl) {
  // Cheap regex first — avoids re-parsing the document for one meta tag.
  const og = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)
    ?? html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  if (og?.[1]) {
    try { return new URL(og[1], baseUrl).toString(); } catch { return og[1]; }
  }
  return null;
}

function presign(s3Key) {
  return getSignedUrl(
    s3,
    new GetObjectCommand({ Bucket: BUCKET, Key: s3Key }),
    { expiresIn: PRESIGN_TTL },
  );
}

function sha256Hex(input) {
  return createHash('sha256').update(input).digest('hex');
}

function safeHost(url) {
  try { return new URL(url).host; } catch { return 'unknown'; }
}

function resp(statusCode, body) {
  return {
    statusCode,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  };
}
