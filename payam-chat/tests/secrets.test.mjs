import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// secrets.mjs uses SecretsManagerClient at module level, so we test
// the parseKey logic by reimplementing it here (same as source).

function parseKey(secretString) {
  const trimmed = secretString.trim();
  if (!trimmed.startsWith('{')) return trimmed;
  try {
    const obj = JSON.parse(trimmed);
    return (
      obj.ANTHROPIC_API_KEY?.trim() ||
      obj.apiKey?.trim() ||
      Object.values(obj).find((v) => typeof v === 'string' && v.trim().length > 0)?.trim() ||
      trimmed
    );
  } catch {
    return trimmed;
  }
}

describe('parseKey (from secrets.mjs)', () => {
  it('returns plain string API key', () => {
    assert.equal(parseKey('sk-ant-abc123'), 'sk-ant-abc123');
  });

  it('trims whitespace from plain string', () => {
    assert.equal(parseKey('  sk-ant-abc  \n'), 'sk-ant-abc');
  });

  it('extracts ANTHROPIC_API_KEY from JSON', () => {
    assert.equal(parseKey('{"ANTHROPIC_API_KEY": "sk-ant-xyz"}'), 'sk-ant-xyz');
  });

  it('extracts apiKey from JSON', () => {
    assert.equal(parseKey('{"apiKey": "sk-ant-456"}'), 'sk-ant-456');
  });

  it('falls back to first string value', () => {
    assert.equal(parseKey('{"customField": "sk-ant-789"}'), 'sk-ant-789');
  });

  it('prefers ANTHROPIC_API_KEY over apiKey', () => {
    assert.equal(
      parseKey('{"ANTHROPIC_API_KEY": "first", "apiKey": "second"}'),
      'first',
    );
  });

  it('handles empty JSON object', () => {
    assert.equal(parseKey('{}'), '{}');
  });

  it('handles malformed JSON starting with {', () => {
    assert.equal(parseKey('{broken'), '{broken');
  });

  it('trims extracted values', () => {
    assert.equal(parseKey('{"ANTHROPIC_API_KEY": "  key  "}'), 'key');
  });

  it('skips empty string values', () => {
    assert.equal(parseKey('{"ANTHROPIC_API_KEY": "", "apiKey": "fallback"}'), 'fallback');
  });
});
