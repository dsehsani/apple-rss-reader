import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { INTENT_CLASSIFIER_SYSTEM } from '../src/prompts/intent.mjs';
import { DISCOVER_SOURCES_SYSTEM } from '../src/prompts/discover-sources.mjs';
import { PARSE_FILTER_RULE_SYSTEM } from '../src/prompts/parse-filter-rule.mjs';

describe('intent classifier prompt', () => {
  it('exports a non-empty string', () => {
    assert.ok(typeof INTENT_CLASSIFIER_SYSTEM === 'string');
    assert.ok(INTENT_CLASSIFIER_SYSTEM.length > 100);
  });

  it('mentions all seven intents', () => {
    const intents = ['source_discovery', 'find_similar', 'feed_audit', 'filter_rule', 'summarize', 'explain', 'unknown'];
    for (const intent of intents) {
      assert.ok(
        INTENT_CLASSIFIER_SYSTEM.includes(intent),
        `Prompt should mention intent: ${intent}`,
      );
    }
  });

  it('includes JSON output schema', () => {
    assert.ok(INTENT_CLASSIFIER_SYSTEM.includes('"intent"'));
    assert.ok(INTENT_CLASSIFIER_SYSTEM.includes('"args"'));
    assert.ok(INTENT_CLASSIFIER_SYSTEM.includes('"confidence"'));
  });

  it('includes worked examples', () => {
    assert.ok(INTENT_CLASSIFIER_SYSTEM.includes('Worked example'));
  });

  it('is long enough for Haiku cache (≥2048 tokens ≈ ≥6000 chars)', () => {
    assert.ok(
      INTENT_CLASSIFIER_SYSTEM.length >= 4000,
      `Prompt length ${INTENT_CLASSIFIER_SYSTEM.length} may be too short for cache`,
    );
  });
});

describe('discover sources prompt', () => {
  it('exports a non-empty string', () => {
    assert.ok(typeof DISCOVER_SOURCES_SYSTEM === 'string');
    assert.ok(DISCOVER_SOURCES_SYSTEM.length > 100);
  });

  it('specifies JSON-only output', () => {
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('JSON only'));
  });

  it('mentions card limit of 5', () => {
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('5'));
  });

  it('includes the output schema fields', () => {
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('feedURL'));
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('oneLine'));
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('alreadySubscribed'));
  });

  it('warns against inventing URLs', () => {
    assert.ok(DISCOVER_SOURCES_SYSTEM.includes('NEVER invent'));
  });
});

describe('parse filter rule prompt', () => {
  it('exports a non-empty string', () => {
    assert.ok(typeof PARSE_FILTER_RULE_SYSTEM === 'string');
    assert.ok(PARSE_FILTER_RULE_SYSTEM.length > 100);
  });

  it('specifies all allowed content kinds', () => {
    const kinds = ['opinion', 'podcast', 'video', 'newsletter', 'press_release', 'live_blog'];
    for (const kind of kinds) {
      assert.ok(
        PARSE_FILTER_RULE_SYSTEM.includes(kind),
        `Should mention content kind: ${kind}`,
      );
    }
  });

  it('includes the output schema fields', () => {
    assert.ok(PARSE_FILTER_RULE_SYSTEM.includes('displayText'));
    assert.ok(PARSE_FILTER_RULE_SYSTEM.includes('predicate'));
    assert.ok(PARSE_FILTER_RULE_SYSTEM.includes('scope'));
    assert.ok(PARSE_FILTER_RULE_SYSTEM.includes('rationale'));
  });

  it('includes worked examples', () => {
    assert.ok(PARSE_FILTER_RULE_SYSTEM.includes('stop showing me opinion pieces'));
  });
});
