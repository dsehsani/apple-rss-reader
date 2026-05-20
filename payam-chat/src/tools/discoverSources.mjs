import { MODELS, callWithCachedSystem, sumUsage } from '../anthropic.mjs';
import { DISCOVER_SOURCES_SYSTEM } from '../prompts/discover-sources.mjs';
import { candidatesForTopic } from '../catalog.mjs';
import { candidatesFromRegistry } from '../registry.mjs';

/**
 * discover_sources tool — returns a card_list view payload.
 * Queries the live feed_registry first; falls back to the static catalog
 * when the registry returns fewer than 3 results.
 *
 * @param {object} args
 * @param {string} args.topic — short topic phrase.
 * @param {string[]} [args.subscribedURLs] — feed URLs the user already follows.
 * @param {object} [args.topicAffinities] — ephemeral topic preferences (never stored).
 * @returns {{view: object, usage: object}}
 */
export async function runDiscoverSources({ topic, subscribedURLs = [], topicAffinities = {} }) {
  if (!topic || typeof topic !== 'string') {
    throw new Error('discover_sources requires a non-empty topic');
  }

  // Try live registry first, fall back to static catalog
  let candidates = await candidatesFromRegistry(topic, { limit: 8 });
  let source = 'registry';

  if (candidates.length < 3) {
    const catalogCandidates = candidatesForTopic(topic, { limit: 8 });
    // Merge: registry results first, then catalog results (deduplicated)
    const seenURLs = new Set(candidates.map((c) => c.feedURL.toLowerCase()));
    for (const c of catalogCandidates) {
      if (!seenURLs.has(c.feedURL.toLowerCase())) {
        candidates.push(c);
        seenURLs.add(c.feedURL.toLowerCase());
      }
    }
    source = candidates.length > 0 ? 'mixed' : 'catalog';
  }

  // Re-rank by topicAffinities if provided (ephemeral, never stored)
  if (Object.keys(topicAffinities).length > 0 && candidates.some((c) => c.qualityScore != null)) {
    candidates = candidates.map((c) => {
      const category = (c.category || '').toLowerCase();
      const boost = topicAffinities[category] || 0;
      return { ...c, _score: (c.qualityScore || 0.5) + boost * 0.3 };
    });
    candidates.sort((a, b) => (b._score || 0) - (a._score || 0));
  }

  // No hits from either source
  if (candidates.length === 0) {
    return {
      view: {
        type: 'card_list',
        payload: {
          topic,
          cards: [],
          emptyReason: 'No matching feeds found. Try a broader topic.',
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
        `- {name: ${JSON.stringify(c.name)}, feedURL: ${JSON.stringify(c.feedURL)}, description: ${JSON.stringify(c.description)}, category: ${JSON.stringify(c.category)}${c.qualityScore != null ? `, qualityScore: ${c.qualityScore}` : ''}${c.subscriberCount != null ? `, subscribers: ${c.subscriberCount}` : ''}}`,
    ),
    '',
    `Already subscribed: ${JSON.stringify(subscribedURLs)}`,
    `Source: ${source}`,
  ].join('\n');

  const { data, usage } = await callWithCachedSystem({
    model: MODELS.HAIKU,
    system: DISCOVER_SOURCES_SYSTEM,
    messages: [{ role: 'user', content: userMsg }],
    maxTokens: 800,
    responseJSON: true,
  });

  // Validate against the candidate set — no hallucinated URLs
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
