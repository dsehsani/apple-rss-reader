// Deterministic key derivation that matches the iOS client.
//
// - feedId(feedUrl) = first 32 hex chars of sha256(canonicalFeedUrl).
// - itemId(feedId, link) = UUID built from the same FNV-1a algorithm as
//   FeedIngestService.swift's `UUID(name:)`, with input "${feedId}|${link}".
//   The follow-up iOS plan will update the client to use the same
//   "feedId|link" input for cloud-delivered items so both sides converge.

import { createHash } from 'node:crypto';

const FNV_OFFSET = 14695981039346656037n;
const FNV_PRIME = 1099511628211n;
const U64_MASK = (1n << 64n) - 1n;

export function canonicalizeFeedUrl(raw) {
  if (!raw) throw new Error('feedUrl required');
  let url = raw.trim();
  if (url.startsWith('http://')) url = 'https://' + url.slice('http://'.length);
  // Lowercase scheme + host only; preserve path/query casing (some feeds care).
  try {
    const u = new URL(url);
    u.protocol = u.protocol.toLowerCase();
    u.host = u.host.toLowerCase();
    return u.toString();
  } catch {
    return url;
  }
}

export function feedIdFor(feedUrl) {
  const canon = canonicalizeFeedUrl(feedUrl);
  return createHash('sha256').update(canon).digest('hex').slice(0, 32);
}

// Mirror of FeedIngestService.swift `UUID(name:)`.
// The Swift implementation does two FNV-1a passes over the input bytes
// (forward, then reversed) without resetting `h`, then writes the
// low-to-high bytes of each 64-bit state into hash[0..7] and hash[8..15],
// stamps RFC 4122 version 5 and variant bits, and emits a UUID string.
export function deterministicUUID(name) {
  const data = Buffer.from(name, 'utf8');
  let h = FNV_OFFSET;

  for (let i = 0; i < data.length; i++) {
    h ^= BigInt(data[i]);
    h = (h * FNV_PRIME) & U64_MASK;
  }
  const out = Buffer.alloc(16);
  for (let i = 0; i < 8; i++) {
    out[i] = Number((h >> BigInt(i * 8)) & 0xFFn);
  }
  for (let i = data.length - 1; i >= 0; i--) {
    h ^= BigInt(data[i]);
    h = (h * FNV_PRIME) & U64_MASK;
  }
  for (let i = 0; i < 8; i++) {
    out[8 + i] = Number((h >> BigInt(i * 8)) & 0xFFn);
  }
  out[6] = (out[6] & 0x0f) | 0x50;
  out[8] = (out[8] & 0x3f) | 0x80;

  const hex = out.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export function itemIdFor(feedId, link) {
  return deterministicUUID(`${feedId}|${link}`);
}

// SQS dedup-id for orchestrator → worker enqueue. Bounded to 128 chars.
export function pollDedupId(feedUrl, lastFetchedAt) {
  return createHash('sha256')
    .update(`${feedUrl}|${lastFetchedAt}`)
    .digest('hex');
}
