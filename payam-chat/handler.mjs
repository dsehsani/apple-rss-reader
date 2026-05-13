import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const SECRET_ID = 'openrss/gemini-api-key';
const GEMINI_GENERATE_PATH =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

/** Canonical system prompt for the in-app assistant (server-side only). */
const BASE_SYSTEM_PROMPT = `You are an AI assistant built into OpenRSS, a modern RSS reader app for iOS. You help users with three things:

1. Summarizing articles — When the user is reading an article, summarize it clearly, highlight key points, and answer follow-up questions about its content based on the article context you are given.

2. Recommending RSS feed URLs — When a user describes their interests, suggest specific real RSS feed URLs they can add to OpenRSS (e.g. https://feeds.npr.org/1001/rss.xml). Always provide actual feed URLs, not just website names.

3. Explaining how to use OpenRSS — Help users navigate the app: adding feeds via the My Feeds tab, organizing feeds into folders, using the Today feed with category filters, bookmarking articles, browsing the Discover tab, and using app Settings.

Keep responses concise and conversational. Use plain text; only use minimal formatting when it genuinely aids clarity.`;

const ALLOWED_ROLES = new Set(['user', 'assistant', 'system']);

const secretsClient = new SecretsManagerClient({});
let cachedApiKey = null;

function jsonResponse(statusCode, bodyObj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(bodyObj),
  };
}

/** Swift `String.prefix(3000)` on Character boundaries ≈ first 3000 Unicode code points in JS. */
function truncateLikeSwift(content) {
  return [...content].slice(0, 3000).join('');
}

function buildSystemPrompt(articleContext) {
  if (articleContext == null) return BASE_SYSTEM_PROMPT;

  const snippet = truncateLikeSwift(articleContext.content);

  return `${BASE_SYSTEM_PROMPT}

---

The user is currently reading an article in OpenRSS:

Title: ${articleContext.title}
Feed: ${articleContext.feedName}

Article content:
${snippet}

Reference this article when answering questions. If asked to summarize it, do so based on the content above.`;
}

function parseApiKeyFromSecret(secretString) {
  const trimmed = secretString.trim();
  if (!trimmed.startsWith('{')) return trimmed;

  try {
    const obj = JSON.parse(trimmed);
    if (typeof obj.GEMINI_API_KEY === 'string' && obj.GEMINI_API_KEY.trim()) {
      return obj.GEMINI_API_KEY.trim();
    }
    if (typeof obj.apiKey === 'string' && obj.apiKey.trim()) {
      return obj.apiKey.trim();
    }
    if (typeof obj.OPENAI_API_KEY === 'string' && obj.OPENAI_API_KEY.trim()) {
      return obj.OPENAI_API_KEY.trim();
    }
    for (const v of Object.values(obj)) {
      if (typeof v === 'string' && v.trim().length > 0) return v.trim();
    }
  } catch {
    return trimmed;
  }
  return trimmed;
}

async function getGeminiApiKey() {
  if (cachedApiKey) return cachedApiKey;

  const out = await secretsClient.send(new GetSecretValueCommand({ SecretId: SECRET_ID }));
  if (!out.SecretString) {
    throw new Error('Secret has no SecretString');
  }
  const key = parseApiKeyFromSecret(out.SecretString);
  if (!key) {
    throw new Error('Could not parse API key from secret');
  }
  cachedApiKey = key;
  return key;
}

function validateMessages(messages) {
  if (!Array.isArray(messages)) {
    return 'messages must be an array of { role, content }';
  }
  if (messages.length === 0) {
    return 'messages must be a non-empty array';
  }
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    if (m == null || typeof m !== 'object') {
      return `messages[${i}] must be an object`;
    }
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

function getHttpMethod(event) {
  return event?.requestContext?.http?.method ?? event?.httpMethod ?? '';
}

function readBody(event) {
  if (!event.body) return '';
  if (event.isBase64Encoded) {
    return Buffer.from(event.body, 'base64').toString('utf8');
  }
  return event.body;
}

function safeGeminiErrorMessage(res, data) {
  if (data && typeof data === 'object' && data.error?.message) {
    return String(data.error.message);
  }
  return `Gemini request failed (${res.status})`;
}

function buildFullSystemInstruction(baseFromArticle, messages) {
  const extra = [];
  for (const m of messages) {
    if (m.role === 'system') {
      extra.push(m.content);
    }
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

export async function main(event) {
  const method = getHttpMethod(event).toUpperCase();
  if (method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed. Use POST.' });
  }

  let payload;
  try {
    const raw = readBody(event);
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  const msgErr = validateMessages(payload.messages);
  if (msgErr) {
    return jsonResponse(400, { error: msgErr });
  }

  const ctxErr = validateArticleContext(payload.articleContext);
  if (ctxErr) {
    return jsonResponse(400, { error: ctxErr });
  }

  let apiKey;
  try {
    apiKey = await getGeminiApiKey();
  } catch (e) {
    console.error('Secrets Manager error:', e.name || 'Error', e.message);
    return jsonResponse(500, { error: 'Failed to load API configuration' });
  }

  const articleContext =
    payload.articleContext != null
      ? {
          title: payload.articleContext.title,
          feedName: payload.articleContext.feedName,
          content: payload.articleContext.content,
        }
      : null;

  const baseSystem = buildSystemPrompt(articleContext);
  const systemText = buildFullSystemInstruction(baseSystem, payload.messages);
  const contents = toGeminiContents(payload.messages);

  const geminiUrl = `${GEMINI_GENERATE_PATH}?key=${encodeURIComponent(apiKey)}`;

  let res;
  let resText;
  try {
    res = await fetch(geminiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemText }] },
        contents,
      }),
    });
    resText = await res.text();
  } catch (e) {
    console.error('Gemini network error:', e.message);
    return jsonResponse(502, { error: 'Failed to reach Gemini' });
  }

  let data;
  try {
    data = resText ? JSON.parse(resText) : {};
  } catch {
    data = {};
  }

  if (!res.ok) {
    const detail = safeGeminiErrorMessage(res, data);
    console.error('Gemini HTTP error:', res.status);
    if (res.status === 401) {
      return jsonResponse(401, { error: detail });
    }
    return jsonResponse(502, { error: detail });
  }

  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') {
    console.error('Gemini unexpected shape');
    return jsonResponse(502, { error: 'Unexpected response from Gemini' });
  }

  return jsonResponse(200, { reply: text });
}
