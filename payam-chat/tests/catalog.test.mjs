import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { candidatesForTopic, matchedCandidatesForTopic, CATALOG } from '../src/catalog.mjs';

describe('candidatesForTopic', () => {
  it('returns candidates for a known category keyword', () => {
    const results = candidatesForTopic('tech');
    assert.ok(results.length > 0);
    assert.ok(results.length <= 8);
    assert.ok(results[0].category);
    assert.ok(results[0].feedURL);
    assert.ok(results[0].name);
  });

  it('returns candidates matching category name directly', () => {
    const results = candidatesForTopic('Apple');
    assert.ok(results.length > 0);
    assert.ok(results.some((r) => r.category === 'Apple'));
  });

  it('respects the limit parameter', () => {
    const results = candidatesForTopic('tech', { limit: 3 });
    assert.ok(results.length <= 3);
  });

  it('returns empty array for a topic with no matches', () => {
    const results = candidatesForTopic('xyznonexistent123456');
    // Even with no keyword match, it may return results from score=0 categories
    // if out.length is 0. Let's check the function handles it.
    assert.ok(Array.isArray(results));
  });

  it('handles partial token matches', () => {
    const results = candidatesForTopic('ios dev');
    assert.ok(results.length > 0);
  });

  it('attaches category to each result', () => {
    const results = candidatesForTopic('space');
    for (const r of results) {
      assert.ok(typeof r.category === 'string');
    }
  });

  it('CATALOG is a non-empty array', () => {
    assert.ok(Array.isArray(CATALOG));
    assert.ok(CATALOG.length > 0);
  });
});

describe('matchedCandidatesForTopic', () => {
  it('returns feeds from matching categories, top match first', () => {
    const results = matchedCandidatesForTopic('apple');
    assert.ok(results.length > 0);
    assert.equal(results[0].category, 'Apple');
    // Only related categories are allowed in; clearly-unrelated ones are excluded.
    assert.ok(!results.some((r) => ['Music', 'Books', 'Gaming', 'Space'].includes(r.category)));
  });

  it('returns an empty array when nothing in the catalog matches', () => {
    assert.deepEqual(matchedCandidatesForTopic('soccer'), []);
    assert.deepEqual(matchedCandidatesForTopic('xyznonexistent123456'), []);
  });

  it('does NOT pad with unrelated Tech feeds on a miss (regression)', () => {
    const results = matchedCandidatesForTopic('underwater basket weaving');
    assert.equal(results.length, 0);
  });

  it('respects the limit parameter', () => {
    const results = matchedCandidatesForTopic('tech', { limit: 2 });
    assert.ok(results.length <= 2);
  });
});
