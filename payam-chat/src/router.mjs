import { MODELS, callWithCachedSystem } from './anthropic.mjs';
import { INTENT_CLASSIFIER_SYSTEM } from './prompts/intent.mjs';

const ALLOWED_INTENTS = new Set([
  'source_discovery',
  'find_similar',
  'feed_audit',
  'filter_rule',
  'summarize',
  'explain',
  'unknown',
]);

/**
 * Classify the user's latest message into a structured intent.
 *
 * @param {Array<{role:string,content:string}>} messages
 * @param {object|null} articleContext
 * @returns {{intent: string, args: object, confidence: number, usage: object}}
 */
export async function classifyIntent(messages, articleContext) {
  const userTurns = messages.filter((m) => m.role === 'user');
  const last = userTurns[userTurns.length - 1];
  if (!last) {
    return {
      intent: 'unknown',
      args: { raw: '' },
      confidence: 0,
      usage: { model: 'none', inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
    };
  }

  const userBody = articleContext
    ? `User message: ${JSON.stringify(last.content)}\n\nArticle context present:\n- Title: ${articleContext.title}\n- Feed: ${articleContext.feedName}`
    : `User message: ${JSON.stringify(last.content)}\n\n(No article context.)`;

  const { data, usage } = await callWithCachedSystem({
    model: MODELS.HAIKU,
    system: INTENT_CLASSIFIER_SYSTEM,
    messages: [{ role: 'user', content: userBody }],
    maxTokens: 200,
    responseJSON: true,
  });

  const intent = ALLOWED_INTENTS.has(data.intent) ? data.intent : 'unknown';
  const args = data.args && typeof data.args === 'object' ? data.args : {};
  const confidence = typeof data.confidence === 'number' ? data.confidence : 0.5;

  return { intent, args, confidence, usage };
}
