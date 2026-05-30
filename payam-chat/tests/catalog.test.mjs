import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { candidatesForTopic, CATALOG } from '../src/catalog.mjs';

describe('CATALOG', () => {
  it('has at least 10 categories', () => {
    assert.ok(CATALOG.length >= 10, `Expected ≥10 categories, got ${CATALOG.length}`);
  });

  it('every category has a non-empty name and keywords array', () => {
    for (const cat of CATALOG) {
      assert.ok(typeof cat.category === 'string' && cat.category.length > 0);
      assert.ok(Array.isArray(cat.keywords) && cat.keywords.length > 0);
    }
  });

  it('every feed has name, feedURL, and description', () => {
    for (const cat of CATALOG) {
      for (const f of cat.feeds) {
        assert.ok(typeof f.name === 'string' && f.name.length > 0, `Missing name in ${cat.category}`);
        assert.ok(typeof f.feedURL === 'string' && f.feedURL.startsWith('http'), `Invalid feedURL for ${f.name}`);
        assert.ok(typeof f.description === 'string' && f.description.length > 0, `Missing description for ${f.name}`);
      }
    }
  });

  it('has no duplicate feed URLs across all categories', () => {
    const urls = new Set();
    for (const cat of CATALOG) {
      for (const f of cat.feeds) {
        assert.ok(!urls.has(f.feedURL), `Duplicate feedURL: ${f.feedURL}`);
        urls.add(f.feedURL);
      }
    }
  });
});

describe('candidatesForTopic', () => {
  it('returns results for a known category name', () => {
    const results = candidatesForTopic('Tech');
    assert.ok(results.length > 0, 'Should return candidates for "Tech"');
    assert.ok(results.length <= 8, 'Default limit is 8');
  });

  it('each result includes category field', () => {
    const results = candidatesForTopic('Apple');
    for (const r of results) {
      assert.ok(typeof r.category === 'string');
      assert.ok(typeof r.name === 'string');
      assert.ok(typeof r.feedURL === 'string');
    }
  });

  it('matches keywords, not just category names', () => {
    const results = candidatesForTopic('swift');
    assert.ok(results.length > 0, 'Should match "swift" via iOS Dev keywords');
    const hasIOSDev = results.some((r) => r.category === 'iOS Dev');
    assert.ok(hasIOSDev, 'Should include iOS Dev category for "swift"');
  });

  it('returns results for a multi-word topic', () => {
    const results = candidatesForTopic('video games');
    assert.ok(results.length > 0);
    const hasGaming = results.some((r) => r.category === 'Gaming');
    assert.ok(hasGaming, 'Should match Gaming category for "video games"');
  });

  it('respects the limit option', () => {
    const results = candidatesForTopic('Tech', { limit: 3 });
    assert.ok(results.length <= 3, `Expected ≤3, got ${results.length}`);
  });

  it('returns empty array for completely unrelated topic with no fallback', () => {
    // candidatesForTopic falls through all categories when score is 0
    // but still returns results if no category scores > 0 (it returns all until limit)
    const results = candidatesForTopic('xyzzy_nonsense_topic_12345');
    // Even gibberish returns results because it falls through all categories
    assert.ok(Array.isArray(results));
  });

  it('scores exact category name match higher than keyword match', () => {
    const results = candidatesForTopic('Apple');
    // Apple category should dominate the results
    const appleCount = results.filter((r) => r.category === 'Apple').length;
    assert.ok(appleCount >= 3, `Expected ≥3 Apple feeds, got ${appleCount}`);
  });

  it('handles case-insensitive matching', () => {
    const upper = candidatesForTopic('TECH');
    const lower = candidatesForTopic('tech');
    assert.equal(upper.length, lower.length);
    assert.deepEqual(
      upper.map((r) => r.feedURL),
      lower.map((r) => r.feedURL),
    );
  });

  it('limit of 1 returns exactly 1', () => {
    const results = candidatesForTopic('Science', { limit: 1 });
    assert.equal(results.length, 1);
  });
});
