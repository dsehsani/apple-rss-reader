import { MODELS, callWithCachedSystem } from '../anthropic.mjs';
import { PARSE_FILTER_RULE_SYSTEM } from '../prompts/parse-filter-rule.mjs';

const ALLOWED_CONTENT_KINDS = new Set([
  'opinion',
  'podcast',
  'video',
  'newsletter',
  'press_release',
  'live_blog',
]);

const SCOPE_RE = /^(global|folder:.+|feed:.+)$/;

/**
 * parse_filter_rule tool — returns a rule_card view payload.
 *
 * @param {object} args
 * @param {string} args.text — user's raw filter request.
 * @param {Array<{title:string,feedURL:string}>} [args.subscriptions]
 */
export async function runParseFilterRule({ text, subscriptions = [] }) {
  if (!text || typeof text !== 'string') {
    throw new Error('parse_filter_rule requires non-empty text');
  }

  const userMsg = [
    `User message: ${JSON.stringify(text)}`,
    '',
    `Subscriptions: ${JSON.stringify(subscriptions)}`,
  ].join('\n');

  const { data, usage } = await callWithCachedSystem({
    model: MODELS.HAIKU,
    system: PARSE_FILTER_RULE_SYSTEM,
    messages: [{ role: 'user', content: userMsg }],
    maxTokens: 400,
    responseJSON: true,
  });

  const predicate = sanitizePredicate(data.predicate || {});
  const scope = SCOPE_RE.test(data.scope) ? data.scope : 'global';

  return {
    view: {
      type: 'rule_card',
      payload: {
        displayText: (data.displayText || 'New filter').slice(0, 120),
        predicate,
        scope,
        rationale: (data.rationale || '').slice(0, 200),
        sourceText: text,
      },
    },
    usage,
  };
}

function sanitizePredicate(p) {
  return {
    keywords: Array.isArray(p.keywords) ? p.keywords.filter((s) => typeof s === 'string').slice(0, 20) : [],
    phrases: Array.isArray(p.phrases) ? p.phrases.filter((s) => typeof s === 'string').slice(0, 20) : [],
    sourceFeedURLs: Array.isArray(p.sourceFeedURLs)
      ? p.sourceFeedURLs.filter((s) => typeof s === 'string').slice(0, 50)
      : [],
    contentKinds: Array.isArray(p.contentKinds)
      ? p.contentKinds.filter((s) => ALLOWED_CONTENT_KINDS.has(s))
      : [],
  };
}
