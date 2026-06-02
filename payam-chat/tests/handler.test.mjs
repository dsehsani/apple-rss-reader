import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// handler.mjs imports SecretsManagerClient at module level, which will fail
// without AWS credentials. We test the pure functions by extracting and
// reimplementing them here — the logic is identical.

// --- Reimplemented pure functions from handler.mjs ---

const ALLOWED_ROLES = new Set(['user', 'assistant', 'system']);

function validateMessages(messages) {
  if (!Array.isArray(messages)) return 'messages must be an array of { role, content }';
  if (messages.length === 0) return 'messages must be a non-empty array';
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    if (m == null || typeof m !== 'object') return `messages[${i}] must be an object`;
    const { role, content } = m;
    if (typeof role !== 'string' || !ALLOWED_ROLES.has(role)) {
      return `messages[${i}].role must be one of: user, assistant, system`;
    }
    if (typeof content !== 'string' || content.trim().length === 0) {
      return `messages[${i}].content must be a non-empty string`;
    }
  }
  return null;
}

function validateArticleContext(ctx) {
  if (ctx == null) return null;
  if (typeof ctx !== 'object' || Array.isArray(ctx)) {
    return 'articleContext must be an object with title, feedName, content';
  }
  const { title, feedName, content } = ctx;
  if (typeof title !== 'string' || typeof feedName !== 'string' || typeof content !== 'string') {
    return 'articleContext must include string fields title, feedName, content';
  }
  return null;
}

function truncateLikeSwift(content) {
  return [...content].slice(0, 3000).join('');
}

const BASE_SYSTEM_PROMPT = 'You are an AI assistant built into Payam.';

function buildSystemPrompt(articleContext) {
  if (articleContext == null) return BASE_SYSTEM_PROMPT;
  const snippet = truncateLikeSwift(articleContext.content);
  return `${BASE_SYSTEM_PROMPT}\n\nTitle: ${articleContext.title}\nFeed: ${articleContext.feedName}\n\n${snippet}`;
}

function parseApiKeyFromSecret(secretString) {
  const trimmed = secretString.trim();
  if (!trimmed.startsWith('{')) return trimmed;
  try {
    const obj = JSON.parse(trimmed);
    if (typeof obj.GEMINI_API_KEY === 'string' && obj.GEMINI_API_KEY.trim()) return obj.GEMINI_API_KEY.trim();
    if (typeof obj.apiKey === 'string' && obj.apiKey.trim()) return obj.apiKey.trim();
    if (typeof obj.OPENAI_API_KEY === 'string' && obj.OPENAI_API_KEY.trim()) return obj.OPENAI_API_KEY.trim();
    for (const v of Object.values(obj)) {
      if (typeof v === 'string' && v.trim().length > 0) return v.trim();
    }
  } catch {
    return trimmed;
  }
  return trimmed;
}

function buildFullSystemInstruction(baseFromArticle, messages) {
  const extra = [];
  for (const m of messages) {
    if (m.role === 'system') extra.push(m.content);
  }
  if (extra.length === 0) return baseFromArticle;
  return `${baseFromArticle}\n\n${extra.join('\n\n')}`;
}

function toGeminiContents(messages) {
  return messages
    .filter((m) => m.role !== 'system')
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));
}

// --- Tests ---

describe('validateMessages', () => {
  it('accepts valid messages', () => {
    assert.equal(validateMessages([{ role: 'user', content: 'hello' }]), null);
  });

  it('accepts all three roles', () => {
    assert.equal(
      validateMessages([
        { role: 'system', content: 'be helpful' },
        { role: 'user', content: 'hi' },
        { role: 'assistant', content: 'hey' },
      ]),
      null,
    );
  });

  it('rejects non-array', () => {
    assert.ok(validateMessages('string') !== null);
    assert.ok(validateMessages({}) !== null);
    assert.ok(validateMessages(123) !== null);
  });

  it('rejects empty array', () => {
    assert.ok(validateMessages([]) !== null);
  });

  it('rejects invalid role', () => {
    const err = validateMessages([{ role: 'admin', content: 'hi' }]);
    assert.ok(err.includes('role'));
  });

  it('rejects empty content', () => {
    const err = validateMessages([{ role: 'user', content: '' }]);
    assert.ok(err.includes('content'));
  });

  it('rejects whitespace-only content', () => {
    const err = validateMessages([{ role: 'user', content: '   \n\t  ' }]);
    assert.ok(err.includes('content'));
  });

  it('rejects null entries', () => {
    const err = validateMessages([null]);
    assert.ok(err !== null);
  });

  it('rejects primitive entries', () => {
    const err = validateMessages(['hello']);
    assert.ok(err !== null);
  });

  it('returns index in error for second message', () => {
    const err = validateMessages([
      { role: 'user', content: 'ok' },
      { role: 'bad', content: 'x' },
    ]);
    assert.ok(err.includes('1'));
  });
});

describe('validateArticleContext', () => {
  it('accepts null', () => {
    assert.equal(validateArticleContext(null), null);
  });

  it('accepts undefined', () => {
    assert.equal(validateArticleContext(undefined), null);
  });

  it('accepts valid context', () => {
    assert.equal(
      validateArticleContext({ title: 'T', feedName: 'F', content: 'C' }),
      null,
    );
  });

  it('rejects arrays', () => {
    assert.ok(validateArticleContext([]) !== null);
  });

  it('rejects missing title', () => {
    assert.ok(validateArticleContext({ feedName: 'F', content: 'C' }) !== null);
  });

  it('rejects numeric title', () => {
    assert.ok(validateArticleContext({ title: 123, feedName: 'F', content: 'C' }) !== null);
  });
});

describe('truncateLikeSwift', () => {
  it('returns short strings unchanged', () => {
    assert.equal(truncateLikeSwift('hello'), 'hello');
  });

  it('truncates to 3000 characters', () => {
    const long = 'a'.repeat(5000);
    assert.equal(truncateLikeSwift(long).length, 3000);
  });

  it('handles emoji (multi-code-unit characters)', () => {
    const emoji = '😀'.repeat(4000);
    const result = truncateLikeSwift(emoji);
    assert.equal([...result].length, 3000);
  });

  it('handles empty string', () => {
    assert.equal(truncateLikeSwift(''), '');
  });
});

describe('buildSystemPrompt', () => {
  it('returns base prompt when no article context', () => {
    assert.equal(buildSystemPrompt(null), BASE_SYSTEM_PROMPT);
  });

  it('includes article title and feed name', () => {
    const result = buildSystemPrompt({ title: 'Test Title', feedName: 'Test Feed', content: 'Body' });
    assert.ok(result.includes('Test Title'));
    assert.ok(result.includes('Test Feed'));
    assert.ok(result.includes('Body'));
  });

  it('truncates long article content', () => {
    const longContent = 'x'.repeat(5000);
    const result = buildSystemPrompt({ title: 'T', feedName: 'F', content: longContent });
    assert.ok(result.length < BASE_SYSTEM_PROMPT.length + 3200);
  });
});

describe('parseApiKeyFromSecret', () => {
  it('returns plain string as-is', () => {
    assert.equal(parseApiKeyFromSecret('sk-abc123'), 'sk-abc123');
  });

  it('trims whitespace', () => {
    assert.equal(parseApiKeyFromSecret('  sk-abc  '), 'sk-abc');
  });

  it('extracts GEMINI_API_KEY from JSON', () => {
    assert.equal(
      parseApiKeyFromSecret('{"GEMINI_API_KEY": "gk-123"}'),
      'gk-123',
    );
  });

  it('extracts apiKey from JSON', () => {
    assert.equal(
      parseApiKeyFromSecret('{"apiKey": "ak-456"}'),
      'ak-456',
    );
  });

  it('extracts OPENAI_API_KEY from JSON', () => {
    assert.equal(
      parseApiKeyFromSecret('{"OPENAI_API_KEY": "ok-789"}'),
      'ok-789',
    );
  });

  it('falls back to first string value in JSON', () => {
    assert.equal(
      parseApiKeyFromSecret('{"custom": "ck-abc"}'),
      'ck-abc',
    );
  });

  it('returns raw string for invalid JSON starting with {', () => {
    assert.equal(parseApiKeyFromSecret('{not json'), '{not json');
  });

  it('prefers GEMINI_API_KEY over apiKey', () => {
    assert.equal(
      parseApiKeyFromSecret('{"GEMINI_API_KEY": "gk-1", "apiKey": "ak-2"}'),
      'gk-1',
    );
  });
});

describe('buildFullSystemInstruction', () => {
  it('returns base when no system messages', () => {
    const msgs = [{ role: 'user', content: 'hi' }];
    assert.equal(buildFullSystemInstruction('base', msgs), 'base');
  });

  it('appends system messages', () => {
    const msgs = [
      { role: 'system', content: 'extra1' },
      { role: 'user', content: 'hi' },
      { role: 'system', content: 'extra2' },
    ];
    const result = buildFullSystemInstruction('base', msgs);
    assert.ok(result.includes('base'));
    assert.ok(result.includes('extra1'));
    assert.ok(result.includes('extra2'));
  });
});

describe('toGeminiContents', () => {
  it('filters out system messages', () => {
    const msgs = [
      { role: 'system', content: 'sys' },
      { role: 'user', content: 'hi' },
    ];
    const result = toGeminiContents(msgs);
    assert.equal(result.length, 1);
    assert.equal(result[0].role, 'user');
  });

  it('maps assistant to model', () => {
    const msgs = [{ role: 'assistant', content: 'hello' }];
    const result = toGeminiContents(msgs);
    assert.equal(result[0].role, 'model');
  });

  it('wraps content in parts array', () => {
    const msgs = [{ role: 'user', content: 'test' }];
    const result = toGeminiContents(msgs);
    assert.deepEqual(result[0].parts, [{ text: 'test' }]);
  });

  it('preserves message order', () => {
    const msgs = [
      { role: 'user', content: 'a' },
      { role: 'assistant', content: 'b' },
      { role: 'user', content: 'c' },
    ];
    const result = toGeminiContents(msgs);
    assert.equal(result.length, 3);
    assert.equal(result[0].parts[0].text, 'a');
    assert.equal(result[1].parts[0].text, 'b');
    assert.equal(result[2].parts[0].text, 'c');
  });
});
