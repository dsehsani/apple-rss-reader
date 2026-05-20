// Tests for the jsdom extraction pipeline (extract-light.mjs).
// Validates HTML → ContentNode conversion, topic inference, and hero image extraction.
// Run: node --test tests/unit/extract-light.test.mjs

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { JSDOM } from "jsdom";
import { Readability } from "@mozilla/readability";

const __dirname = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(__dirname, "..", "fixtures");

// --- Extracted from extract-light.mjs for unit testing ---

const TOPIC_KEYWORDS = {
  technology: ["software", "hardware", "tech", "digital", "computing"],
  ai: ["artificial intelligence", "machine learning", "llm", "neural network", "deep learning"],
  programming: ["javascript", "python", "rust", "typescript", "react", "node.js", "framework"],
  science: ["research", "study finds", "scientists", "experiment"],
};

function inferTopics(title, textContent) {
  const text = `${title} ${textContent.substring(0, 2000)}`.toLowerCase();
  const topics = [];
  for (const [topic, keywords] of Object.entries(TOPIC_KEYWORDS)) {
    if (keywords.some((kw) => text.includes(kw))) {
      topics.push(topic);
    }
  }
  return topics.slice(0, 5);
}

function extractHeroImage(html) {
  const ogMatch = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i);
  if (ogMatch) return ogMatch[1];
  const ogMatch2 = html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i);
  if (ogMatch2) return ogMatch2[1];
  return null;
}

function htmlToContentNodes(html) {
  const dom = new JSDOM(html);
  const doc = dom.window.document;
  const nodes = [];

  function walk(el) {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "paragraph", text });
        continue;
      }
      if (child.nodeType !== 1) continue;
      const tag = child.tagName.toLowerCase();

      if (["h1", "h2", "h3", "h4", "h5", "h6"].includes(tag)) {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "heading", level: parseInt(tag[1]), text });
      } else if (tag === "p") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "paragraph", text });
      } else if (tag === "img") {
        const src = child.getAttribute("src");
        if (src) nodes.push({ type: "image", url: src, caption: child.getAttribute("alt") || null });
      } else if (tag === "blockquote") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "blockquote", text });
      } else if (tag === "ul" || tag === "ol") {
        const items = Array.from(child.querySelectorAll("li")).map((li) => li.textContent.trim()).filter(Boolean);
        if (items.length > 0) nodes.push({ type: "list", items, ordered: tag === "ol" });
      } else if (tag === "pre" || tag === "code") {
        const text = child.textContent.trim();
        if (text) nodes.push({ type: "codeBlock", text });
      } else if (tag === "figure") {
        const img = child.querySelector("img");
        const caption = child.querySelector("figcaption");
        if (img?.getAttribute("src")) {
          nodes.push({ type: "image", url: img.getAttribute("src"), caption: caption?.textContent?.trim() || null });
        } else {
          walk(child);
        }
      } else {
        walk(child);
      }
    }
  }

  walk(doc.body || doc);
  return nodes;
}
// --- End extracted functions ---

describe("Topic Inference", () => {
  it("detects AI topics", () => {
    const topics = inferTopics("Machine Learning in Production", "Deep learning models deployed at scale");
    assert.ok(topics.includes("ai"), `Expected 'ai' in [${topics}]`);
  });

  it("detects multiple topics", () => {
    const topics = inferTopics(
      "Building ML Pipelines with Python",
      "This software framework uses machine learning and python for research"
    );
    assert.ok(topics.includes("ai"), `Expected 'ai' in [${topics}]`);
    assert.ok(topics.includes("programming"), `Expected 'programming' in [${topics}]`);
  });

  it("returns empty for unrelated content", () => {
    const topics = inferTopics("My Favorite Recipes", "Today we made a delicious pasta with tomato sauce");
    assert.equal(topics.length, 0);
  });

  it("caps at 5 topics", () => {
    const topics = inferTopics(
      "Everything Tech",
      "software hardware machine learning javascript python rust scientists research digital computing"
    );
    assert.ok(topics.length <= 5, `Expected <= 5 topics, got ${topics.length}`);
  });
});

describe("Hero Image Extraction", () => {
  it("extracts og:image", () => {
    const html = readFileSync(join(fixturesDir, "article-simple.html"), "utf-8");
    const hero = extractHeroImage(html);
    assert.equal(hero, "https://example.com/hero.jpg");
  });

  it("returns null when no og:image", () => {
    const html = "<html><head><title>No image</title></head><body></body></html>";
    const hero = extractHeroImage(html);
    assert.equal(hero, null);
  });

  it("handles reversed attribute order", () => {
    const html = '<meta content="https://example.com/img.png" property="og:image"/>';
    const hero = extractHeroImage(html);
    assert.equal(hero, "https://example.com/img.png");
  });
});

describe("HTML → ContentNode Conversion", () => {
  it("converts article HTML to structured nodes", () => {
    const html = readFileSync(join(fixturesDir, "article-simple.html"), "utf-8");

    // Use Readability first (like the real pipeline)
    const dom = new JSDOM(html, { url: "https://example.com/article" });
    const article = new Readability(dom.window.document).parse();
    assert.ok(article, "Readability should parse the article");
    assert.ok(article.title, "Should have a title");

    const nodes = htmlToContentNodes(article.content);

    // Check node types
    const types = nodes.map((n) => n.type);
    assert.ok(types.includes("paragraph"), "Should have paragraphs");
    assert.ok(types.includes("heading"), "Should have headings");

    // Check word count
    const wordCount = nodes
      .filter((n) => n.type === "paragraph" || n.type === "heading")
      .reduce((sum, n) => sum + (n.text?.split(/\s+/).length || 0), 0);
    assert.ok(wordCount > 100, `Should have > 100 words, got ${wordCount}`);
  });

  it("handles images with figures and captions", () => {
    const html = `<div>
      <figure>
        <img src="https://example.com/photo.jpg" alt="Photo"/>
        <figcaption>A test photo</figcaption>
      </figure>
    </div>`;
    const nodes = htmlToContentNodes(html);
    const img = nodes.find((n) => n.type === "image");
    assert.ok(img, "Should have an image node");
    assert.equal(img.url, "https://example.com/photo.jpg");
    assert.equal(img.caption, "A test photo");
  });

  it("handles lists", () => {
    const html = "<ul><li>Item A</li><li>Item B</li><li>Item C</li></ul>";
    const nodes = htmlToContentNodes(html);
    const list = nodes.find((n) => n.type === "list");
    assert.ok(list, "Should have a list node");
    assert.equal(list.items.length, 3);
    assert.equal(list.ordered, false);
  });

  it("handles blockquotes", () => {
    const html = "<blockquote>A famous quote</blockquote>";
    const nodes = htmlToContentNodes(html);
    const quote = nodes.find((n) => n.type === "blockquote");
    assert.ok(quote, "Should have a blockquote");
    assert.equal(quote.text, "A famous quote");
  });
});

describe("Readability Integration", () => {
  it("extracts clean article from full HTML page", () => {
    const html = readFileSync(join(fixturesDir, "article-simple.html"), "utf-8");
    const dom = new JSDOM(html, { url: "https://example.com/article" });
    const article = new Readability(dom.window.document).parse();

    assert.ok(article, "Should parse successfully");
    assert.ok(article.title.length > 0, "Should have a title");
    assert.ok(article.content.length > 200, "Should have substantial content");
    assert.ok(article.textContent.length > 100, "Should have text content");
  });

  it("returns null for non-article pages", () => {
    const html = "<html><body><nav>Menu</nav><footer>Copyright</footer></body></html>";
    const dom = new JSDOM(html, { url: "https://example.com" });
    const article = new Readability(dom.window.document).parse();
    // Readability may return null or very thin content for non-article pages
    if (article) {
      assert.ok(
        article.textContent.trim().length < 50,
        "Non-article should have minimal content"
      );
    }
  });
});
