// Tests for RSS/Atom parsing via rss-parser (replacing the old regex parser).
// Run: node --test tests/unit/feed-parser.test.mjs

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Parser from "rss-parser";

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(__dirname, "..", "fixtures");

const parser = new Parser({
  customFields: {
    item: [
      ["media:thumbnail", "mediaThumbnail", { keepArray: false }],
      ["media:content", "mediaContent", { keepArray: false }],
      ["enclosure"],
    ],
  },
});

describe("RSS Parser", () => {
  it("parses standard RSS 2.0 feed", async () => {
    const xml = readFileSync(join(fixturesDir, "rss-simple.xml"), "utf-8");
    const feed = await parser.parseString(xml);

    assert.equal(feed.title, "Test Blog");
    assert.ok(feed.items.length >= 2, `Expected at least 2 items, got ${feed.items.length}`);

    const first = feed.items[0];
    assert.equal(first.title, "First Post");
    assert.equal(first.link, "https://test.example.com/first-post");
    assert.ok(first.pubDate, "Should have pubDate");
    assert.equal(first.creator || first.author, "Test Author");
  });

  it("parses CDATA content in RSS", async () => {
    const xml = readFileSync(join(fixturesDir, "rss-simple.xml"), "utf-8");
    const feed = await parser.parseString(xml);

    const second = feed.items[1];
    assert.equal(second.title, "Second Post");
    // contentSnippet should strip HTML from CDATA
    assert.ok(
      second.contentSnippet?.includes("HTML") || second.content?.includes("HTML"),
      "Should parse CDATA content"
    );
  });

  it("parses Atom feeds", async () => {
    const xml = readFileSync(join(fixturesDir, "atom-basic.xml"), "utf-8");
    const feed = await parser.parseString(xml);

    assert.equal(feed.title, "Atom Test Feed");
    assert.equal(feed.items.length, 2);

    const first = feed.items[0];
    assert.equal(first.title, "Atom Entry One");
    assert.equal(first.link, "https://atom.example.com/entry-one");
    assert.ok(first.isoDate || first.pubDate, "Should have a date");
  });

  it("handles items without title gracefully", async () => {
    const xml = readFileSync(join(fixturesDir, "rss-simple.xml"), "utf-8");
    const feed = await parser.parseString(xml);

    // rss-parser includes all items; our worker code filters empty titles
    const filtered = feed.items.filter((i) => i.title?.trim());
    assert.equal(filtered.length, 2, "Should have 2 items with titles");
  });

  it("rejects malformed XML with an error", async () => {
    const badXml = "<rss><channel><item><title>Broken";
    await assert.rejects(
      () => parser.parseString(badXml),
      "Should throw on malformed XML"
    );
  });
});
