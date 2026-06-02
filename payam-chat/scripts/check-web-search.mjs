// Diagnostic: confirm the Anthropic API key has the web_search tool enabled.
//
// Makes ONE minimal web-search request and reports a clear verdict. Run with:
//   node scripts/check-web-search.mjs
//
// Exit code 0 = web search works; 1 = it is NOT enabled / something failed.

import Anthropic from '@anthropic-ai/sdk';
import { getAnthropicApiKey } from '../src/secrets.mjs';
import { MODELS } from '../src/anthropic.mjs';

const key = await getAnthropicApiKey();
const client = new Anthropic({ apiKey: key });

try {
  const res = await client.messages.create({
    model: MODELS.SONNET,
    max_tokens: 256,
    tools: [{ type: 'web_search_20250305', name: 'web_search', max_uses: 1 }],
    messages: [{ role: 'user', content: 'Use web search to find the official RSS feed URL for BBC World News. Reply with just the URL.' }],
  });

  const usedSearch = res.content.some(
    (b) => b.type === 'server_tool_use' || b.type === 'web_search_tool_result',
  );
  const text = res.content.filter((b) => b.type === 'text').map((b) => b.text).join(' ').trim();

  console.log('\n✅ WEB SEARCH IS ENABLED.');
  console.log('   The API accepted the web_search tool.');
  console.log('   Model actually ran a search:', usedSearch ? 'yes' : 'no (answered from memory)');
  console.log('   Model replied:', text.slice(0, 200));
  process.exit(0);
} catch (e) {
  const msg = e?.message || String(e);
  const looksDisabled = /web.?search|tool|not.*enabled|permission|unsupported|invalid_request/i.test(msg);
  console.log('\n❌ WEB SEARCH CALL FAILED.');
  console.log('   Error:', msg);
  if (looksDisabled) {
    console.log('\n   This looks like web search is NOT enabled for this account/key.');
    console.log('   Enable it in the Anthropic Console → Settings, then re-run this check.');
  } else {
    console.log('\n   This may be a network/credentials issue rather than web search itself.');
  }
  process.exit(1);
}
