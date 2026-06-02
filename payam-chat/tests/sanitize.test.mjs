import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// sanitizePredicate is not exported from parseFilterRule.mjs, so we
// reimplement and test the identical logic here. This mirrors the
// function at lines 59-70 of parseFilterRule.mjs.

const ALLOWED_CONTENT_KINDS = new Set([
  'opinion', 'podcast', 'video', 'newsletter', 'press_release', 'live_blog',
]);

function sanitizePredicate(p) {
  return {
    keywords: Array.isArray(p.keywords) ? p.keywords.filter((s) => typeof s === 'string').slice(0, 20) : [],
    phrases: Array.isArray(p.phrases) ? p.phrases.filter((s) => typeof s === 'string').slice(0, 20) : [],
    sourceFeedURLs: Array.isArray(p.sourceFeedURLs)
      ? p.sourceFeedURLs.filter((s) => typeof s === 'string').slice(0, 50)
      : [],
    contentKinds: Array.isArray(p.contentKinds)
      ? p.contentKinds.filter((s) => ALLOWED_CONTENT_KINDS.has(s))
      : [],
  };
}

const SCOPE_RE = /^(global|folder:.+|feed:.+)$/;

describe('sanitizePredicate', () => {
  it('returns empty arrays for empty input', () => {
    const result = sanitizePredicate({});
    assert.deepEqual(result, {
      keywords: [],
      phrases: [],
      sourceFeedURLs: [],
      contentKinds: [],
    });
  });

  it('passes through valid keywords', () => {
    const result = sanitizePredicate({ keywords: ['apple', 'google'] });
    assert.deepEqual(result.keywords, ['apple', 'google']);
  });

  it('filters non-string keywords', () => {
    const result = sanitizePredicate({ keywords: ['valid', 123, null, 'also valid'] });
    assert.deepEqual(result.keywords, ['valid', 'also valid']);
  });

  it('limits keywords to 20', () => {
    const many = Array.from({ length: 30 }, (_, i) => `kw${i}`);
    const result = sanitizePredicate({ keywords: many });
    assert.equal(result.keywords.length, 20);
  });

  it('passes through valid phrases', () => {
    const result = sanitizePredicate({ phrases: ['breaking news'] });
    assert.deepEqual(result.phrases, ['breaking news']);
  });

  it('filters non-string phrases', () => {
    const result = sanitizePredicate({ phrases: ['valid', 42, undefined] });
    assert.deepEqual(result.phrases, ['valid']);
  });

  it('limits phrases to 20', () => {
    const many = Array.from({ length: 25 }, (_, i) => `phrase${i}`);
    const result = sanitizePredicate({ phrases: many });
    assert.equal(result.phrases.length, 20);
  });

  it('passes through valid source feed URLs', () => {
    const urls = ['https://example.com/feed'];
    const result = sanitizePredicate({ sourceFeedURLs: urls });
    assert.deepEqual(result.sourceFeedURLs, urls);
  });

  it('limits sourceFeedURLs to 50', () => {
    const many = Array.from({ length: 60 }, (_, i) => `https://feed${i}.com`);
    const result = sanitizePredicate({ sourceFeedURLs: many });
    assert.equal(result.sourceFeedURLs.length, 50);
  });

  it('filters non-string sourceFeedURLs', () => {
    const result = sanitizePredicate({ sourceFeedURLs: ['valid', 123] });
    assert.deepEqual(result.sourceFeedURLs, ['valid']);
  });

  it('passes through valid content kinds', () => {
    const result = sanitizePredicate({ contentKinds: ['opinion', 'podcast'] });
    assert.deepEqual(result.contentKinds, ['opinion', 'podcast']);
  });

  it('filters invalid content kinds', () => {
    const result = sanitizePredicate({ contentKinds: ['opinion', 'spam', 'video', 'fake'] });
    assert.deepEqual(result.contentKinds, ['opinion', 'video']);
  });

  it('rejects all invalid content kinds', () => {
    const result = sanitizePredicate({ contentKinds: ['invalid', 'nope'] });
    assert.deepEqual(result.contentKinds, []);
  });

  it('handles all six valid content kinds', () => {
    const all = ['opinion', 'podcast', 'video', 'newsletter', 'press_release', 'live_blog'];
    const result = sanitizePredicate({ contentKinds: all });
    assert.deepEqual(result.contentKinds, all);
  });

  it('handles non-array inputs for all fields', () => {
    const result = sanitizePredicate({
      keywords: 'not an array',
      phrases: 123,
      sourceFeedURLs: null,
      contentKinds: {},
    });
    assert.deepEqual(result.keywords, []);
    assert.deepEqual(result.phrases, []);
    assert.deepEqual(result.sourceFeedURLs, []);
    assert.deepEqual(result.contentKinds, []);
  });
});

describe('SCOPE_RE (filter rule scope validation)', () => {
  it('accepts "global"', () => {
    assert.ok(SCOPE_RE.test('global'));
  });

  it('accepts folder scopes', () => {
    assert.ok(SCOPE_RE.test('folder:Apple'));
    assert.ok(SCOPE_RE.test('folder:My Tech Feeds'));
  });

  it('accepts feed scopes', () => {
    assert.ok(SCOPE_RE.test('feed:https://example.com/feed'));
  });

  it('rejects empty string', () => {
    assert.ok(!SCOPE_RE.test(''));
  });

  it('rejects unknown scopes', () => {
    assert.ok(!SCOPE_RE.test('user:123'));
    assert.ok(!SCOPE_RE.test('local'));
  });

  it('rejects partial matches', () => {
    assert.ok(!SCOPE_RE.test('folder:'));
    assert.ok(!SCOPE_RE.test('feed:'));
  });
});
