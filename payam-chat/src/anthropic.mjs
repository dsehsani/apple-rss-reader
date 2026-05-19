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
    const reconstructed = '{' + text;
    try {
      return { data: JSON.parse(reconstructed), raw: reconstructed, usage };
    } catch (e) {
      throw new Error(`Model returned invalid JSON: ${e.message}\n--- raw ---\n${reconstructed}`);
    }
  }

  return { data: text, raw: text, usage };
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
