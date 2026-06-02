import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { validateFeed, validateFeeds } from '../src/feedValidator.mjs';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

const RSS = `<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Example Soccer News</title>
    <link>https://soccer.example</link>
    <item><title>Team wins the cup</title><link>https://soccer.example/1</link></item>
    <item><title>Transfer window opens</title><link>https://soccer.example/2</link></item>
    <item><title>Star striker injured</title><link>https://soccer.example/3</link></item>
    <item><title>Fourth headline</title></item>
  </channel>
</rss>`;

const ATOM = `<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Example</title>
  <link rel="self" href="https://atom.example/feed.xml"/>
  <link rel="alternate" href="https://atom.example"/>
  <entry><title>First entry</title></entry>
</feed>`;

const EMPTY_FEED = `<?xml version="1.0"?><rss version="2.0"><channel><title>Empty</title></channel></rss>`;
const HTML = `<!DOCTYPE html><html><head><title>Not a feed</title></head><body>hi</body></html>`;

/** Install a mocked global fetch; the validator resolves fetch at call time. */
async function withFetch(fetchMock) {
  globalThis.fetch = fetchMock;
  return { validateFeed, validateFeeds };
}

function okResponse(body, { status = 200 } = {}) {
  return { ok: status >= 200 && status < 300, status, text: async () => body };
}

describe('validateFeed', () => {
  it('accepts a valid RSS feed and extracts title + headlines', async () => {
    const { validateFeed } = await withFetch(async () => okResponse(RSS));
    const r = await validateFeed('https://soccer.example/feed');
    assert.equal(r.ok, true);
    assert.equal(r.title, 'Example Soccer News');
    assert.equal(r.websiteURL, 'https://soccer.example');
    assert.equal(r.sampleHeadlines.length, 3); // capped at 3 by extractor
    assert.equal(r.sampleHeadlines[0], 'Team wins the cup');
  });

  it('accepts a valid Atom feed and uses the alternate link as website', async () => {
    const { validateFeed } = await withFetch(async () => okResponse(ATOM));
    const r = await validateFeed('https://atom.example/feed.xml');
    assert.equal(r.ok, true);
    assert.equal(r.websiteURL, 'https://atom.example');
    assert.equal(r.sampleHeadlines[0], 'First entry');
  });

  it('rejects a non-http url without fetching', async () => {
    let called = false;
    const { validateFeed } = await withFetch(async () => { called = true; return okResponse(RSS); });
    const r = await validateFeed('ftp://nope');
    assert.equal(r.ok, false);
    assert.equal(called, false);
  });

  it('rejects a non-2xx response', async () => {
    const { validateFeed } = await withFetch(async () => okResponse('nope', { status: 404 }));
    const r = await validateFeed('https://x.example/feed');
    assert.equal(r.ok, false);
    assert.match(r.reason, /http 404/);
  });

  it('rejects an HTML page that is not a feed', async () => {
    const { validateFeed } = await withFetch(async () => okResponse(HTML));
    const r = await validateFeed('https://x.example/');
    assert.equal(r.ok, false);
    assert.match(r.reason, /not a feed/);
  });

  it('rejects a feed with no items', async () => {
    const { validateFeed } = await withFetch(async () => okResponse(EMPTY_FEED));
    const r = await validateFeed('https://x.example/feed');
    assert.equal(r.ok, false);
    assert.match(r.reason, /no items/);
  });

  it('falls back to URL origin when feed has no usable link', async () => {
    const noLink = `<rss><channel><title>NL</title><item><title>One</title></item></channel></rss>`;
    const { validateFeed } = await withFetch(async () => okResponse(noLink));
    const r = await validateFeed('https://host.example/path/feed.xml');
    assert.equal(r.websiteURL, 'https://host.example');
  });

  it('treats an aborted request as a timeout failure', async () => {
    const { validateFeed } = await withFetch(async () => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      throw err;
    });
    const r = await validateFeed('https://slow.example/feed', { timeoutMs: 5 });
    assert.equal(r.ok, false);
    assert.equal(r.reason, 'timeout');
  });

  it('decodes CDATA and entities in titles', async () => {
    const feed = `<rss><channel><title><![CDATA[Tom & Jerry]]></title><item><title>A &amp; B</title></item></channel></rss>`;
    const { validateFeed } = await withFetch(async () => okResponse(feed));
    const r = await validateFeed('https://x.example/feed');
    assert.equal(r.title, 'Tom & Jerry');
    assert.equal(r.sampleHeadlines[0], 'A & B');
  });
});

describe('validateFeeds', () => {
  it('returns only the feeds that pass, dropping failures', async () => {
    const { validateFeeds } = await withFetch(async (url) =>
      url.includes('good') ? okResponse(RSS) : okResponse(HTML),
    );
    const out = await validateFeeds([
      'https://good.example/feed',
      'https://bad.example/feed',
      'https://good2.example/feed',
    ]);
    assert.equal(out.length, 2);
    assert.ok(out.every((r) => r.ok));
  });

  it('never throws even if a fetch rejects', async () => {
    const { validateFeeds } = await withFetch(async (url) => {
      if (url.includes('boom')) throw new Error('network down');
      return okResponse(RSS);
    });
    const out = await validateFeeds(['https://ok.example/feed', 'https://boom.example/feed']);
    assert.equal(out.length, 1);
  });
});
