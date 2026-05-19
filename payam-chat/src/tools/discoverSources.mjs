import { MODELS, callWithCachedSystem, sumUsage } from '../anthropic.mjs';
import { DISCOVER_SOURCES_SYSTEM } from '../prompts/discover-sources.mjs';
import { candidatesForTopic } from '../catalog.mjs';

/**
 * discover_sources tool — returns a card_list view payload.
 *
 * @param {object} args
 * @param {string} args.topic — short topic phrase.
 * @param {string[]} [args.subscribedURLs] — feed URLs the user already follows.
 * @returns {{view: object, usage: object}}
 */
export async function runDiscoverSources({ topic, subscribedURLs = [] }) {
  if (!topic || typeof topic !== 'string') {
    throw new Error('discover_sources requires a non-empty topic');
  }

  const candidates = candidatesForTopic(topic, { limit: 8 });

  // No catalog hits — return an empty card list rather than fabricating feeds.
  // (A future pass can call Sonnet with web search grounding to suggest novel URLs.)
  if (candidates.length === 0) {
    return {
      view: {
        type: 'card_list',
        payload: {
          topic,
          cards: [],
          emptyReason: 'No matching feeds in Payam\'s curated catalog. Try a broader topic.',
        },
      },
      usage: { model: 'none', inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
    };
  }

  const subscribedLower = new Set(subscribedURLs.map((u) => u.toLowerCase()));

  const userMsg = [
    `Topic: "${topic}"`,
    '',
    'Candidates:',
    ...candidates.map(
      (c) =>
        `- {name: ${JSON.stringify(c.name)}, feedURL: ${JSON.stringify(c.feedURL)}, description: ${JSON.stringify(c.description)}, category: ${JSON.stringify(c.category)}}`,
    ),
    '',
    `Already subscribed: ${JSON.stringify(subscribedURLs)}`,
  ].join('\n');

  const { data, usage } = await callWithCachedSystem({
    model: MODELS.HAIKU,
    system: DISCOVER_SOURCES_SYSTEM,
    messages: [{ role: 'user', content: userMsg }],
    maxTokens: 800,
    responseJSON: true,
  });

  // Validate + correct the model's output against the candidate set so we never
  // surface a feed URL that wasn't in the catalog (no hallucinated URLs).
  const validURLs = new Set(candidates.map((c) => c.feedURL));
  const cards = (data.cards || []).filter((c) => validURLs.has(c.feedURL)).map((c) => ({
    name: c.name,
    feedURL: c.feedURL,
    websiteURL: c.websiteURL ?? null,
    oneLine: c.oneLine ?? '',
    sampleHeadlines: Array.isArray(c.sampleHeadlines) ? c.sampleHeadlines : [],
    why: c.why ?? null,
    alreadySubscribed: subscribedLower.has(c.feedURL.toLowerCase()),
  }));

  return {
    view: {
      type: 'card_list',
      payload: { topic, cards },
    },
    usage,
  };
}
