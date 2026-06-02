import Anthropic from '@anthropic-ai/sdk';
import { getAnthropicApiKey } from './secrets.mjs';

// Model IDs — kept aligned with the plan. Update here when the user wants to pin
// to a different revision; consumers never reference raw strings.
export const MODELS = {
  HAIKU: 'claude-haiku-4-5-20251001',
  SONNET: 'claude-sonnet-4-6',
};

let cachedClient = null;

async function getClient() {
  if (cachedClient) return cachedClient;
  const apiKey = await getAnthropicApiKey();
  cachedClient = new Anthropic({ apiKey });
  return cachedClient;
}

/**
 * Issue a Messages call with a cached system prompt.
 *
 * The system prompt is sent as a single content block with
 * `cache_control: { type: 'ephemeral' }`. The cache prefix has to be ≥ 2048 tokens
 * for Haiku and ≥ 1024 for Sonnet — keep tool prompts comfortably above 2048.
 */
export async function callWithCachedSystem({
  model,
  system,
  messages,
  maxTokens,
  responseJSON = false,
}) {
  const client = await getClient();

  const systemBlocks = [
    {
      type: 'text',
      text: system,
      cache_control: { type: 'ephemeral' },
    },
  ];

  const finalMessages = responseJSON
    ? [
        ...messages,
        // Pre-fill the assistant turn with `{` to nudge JSON-only output.
        { role: 'assistant', content: '{' },
      ]
    : messages;

  const res = await client.messages.create({
    model,
    max_tokens: maxTokens,
    system: systemBlocks,
    messages: finalMessages,
  });

  const text = res.content
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('');

  const usage = {
    model,
    inputTokens: res.usage?.input_tokens ?? 0,
    cachedInputTokens: res.usage?.cache_read_input_tokens ?? 0,
    cacheCreationInputTokens: res.usage?.cache_creation_input_tokens ?? 0,
    outputTokens: res.usage?.output_tokens ?? 0,
  };

  if (responseJSON) {
    // The assistant turn is pre-filled with `{`, so the model continues the JSON
    // object — but it sometimes keeps writing prose after the closing brace. Extract
    // the first balanced object (same robust path callWithWebSearch uses) instead of
    // parsing the whole string, which would throw on any trailing text.
    const reconstructed = '{' + text;
    const json = extractJSONObject(reconstructed);
    if (json == null) {
      throw new Error(`Model returned no JSON object\n--- raw ---\n${reconstructed}`);
    }
    try {
      return { data: JSON.parse(json), raw: json, usage };
    } catch (e) {
      throw new Error(`Model returned invalid JSON: ${e.message}\n--- raw ---\n${json}`);
    }
  }

  return { data: text, raw: text, usage };
}

/**
 * Issue a Messages call with the server-side `web_search` tool enabled.
 *
 * Unlike `callWithCachedSystem`, this does NOT pre-fill the assistant turn with `{`
 * (that conflicts with the tool_use blocks the model emits while searching). The
 * model runs its searches server-side and returns the final answer in this single
 * call; we concatenate the text blocks and, when `responseJSON` is set, extract the
 * first balanced `{...}` object from that text.
 *
 * The system prompt is cached (ephemeral) just like `callWithCachedSystem`.
 */
export async function callWithWebSearch({
  model,
  system,
  messages,
  maxTokens,
  responseJSON = false,
  maxUses = 3,
}) {
  const client = await getClient();

  const res = await client.messages.create({
    model,
    max_tokens: maxTokens,
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    tools: [{ type: 'web_search_20250305', name: 'web_search', max_uses: maxUses }],
    messages,
  });

  const text = res.content
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('\n');

  const usage = {
    model,
    inputTokens: res.usage?.input_tokens ?? 0,
    cachedInputTokens: res.usage?.cache_read_input_tokens ?? 0,
    cacheCreationInputTokens: res.usage?.cache_creation_input_tokens ?? 0,
    outputTokens: res.usage?.output_tokens ?? 0,
  };

  if (responseJSON) {
    const json = extractJSONObject(text);
    if (json == null) {
      throw new Error(`Web-search model returned no JSON object\n--- raw ---\n${text}`);
    }
    try {
      return { data: JSON.parse(json), raw: json, usage };
    } catch (e) {
      throw new Error(`Web-search model returned invalid JSON: ${e.message}\n--- raw ---\n${json}`);
    }
  }

  return { data: text, raw: text, usage };
}

/**
 * Extract the first balanced top-level JSON object from a string that may contain
 * surrounding prose or markdown fences. Returns the object substring or null.
 */
export function extractJSONObject(text) {
  if (typeof text !== 'string') return null;
  const start = text.indexOf('{');
  if (start === -1) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

/**
 * Sum a list of usage objects into a single rolled-up usage payload.
 * Used when a single agent call hops through multiple model invocations
 * (classifier → tool) and we want to attribute total cost to the response.
 */
export function sumUsage(parts) {
  const out = {
    model: parts.map((p) => p.model).join('+'),
    inputTokens: 0,
    cachedInputTokens: 0,
    cacheCreationInputTokens: 0,
    outputTokens: 0,
  };
  for (const p of parts) {
    out.inputTokens += p.inputTokens || 0;
    out.cachedInputTokens += p.cachedInputTokens || 0;
    out.cacheCreationInputTokens += p.cacheCreationInputTokens || 0;
    out.outputTokens += p.outputTokens || 0;
  }
  return out;
}
