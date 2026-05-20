// SQS → This Lambda
// Lightweight article extraction using jsdom + Readability (no browser).
// Handles ~80% of articles. On failure or thin content, re-enqueues to
// the Puppeteer Fargate queue for JavaScript-rendered extraction.

import { JSDOM } from "jsdom";
import { Readability } from "@mozilla/readability";
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { query } from "./db.mjs";
import crypto from "node:crypto";

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const sqs = new SQSClient({});

const INDEX_TABLE = process.env.EXTRACTION_INDEX_TABLE || "payam-extraction-index";
const BUCKET = process.env.EXTRACTION_BUCKET || "payam-extractions";
const PUPPETEER_QUEUE_URL = process.env.EXTRACTION_QUEUE_URL; // Fargate fallback

const MIN_WORD_COUNT = 100;
const TTL_HOURS = 72;

// Fixed topic vocabulary for lightweight classification
const TOPIC_KEYWORDS = {
  technology:   ["software", "hardware", "tech", "digital", "computing", "computer", "silicon", "gadget"],
  ai:           ["artificial intelligence", "machine learning", "llm", "neural network", "gpt", "claude", "deep learning", "transformer", "chatbot"],
  ios:          ["swift", "swiftui", "xcode", "uikit", "ios", "iphone", "ipad", "apple developer"],
  apple:        ["apple", "macos", "macbook", "wwdc", "app store", "safari"],
  programming:  ["javascript", "python", "rust", "golang", "typescript", "react", "node.js", "api", "framework", "open source", "github"],
  science:      ["research", "study finds", "scientists", "journal", "experiment", "hypothesis", "peer review", "physics", "biology", "chemistry"],
  business:     ["startup", "funding", "revenue", "ipo", "acquisition", "valuation", "market", "investor", "venture capital"],
  gaming:       ["game", "gaming", "playstation", "xbox", "nintendo", "steam", "esports"],
  security:     ["vulnerability", "exploit", "malware", "ransomware", "cybersecurity", "privacy", "encryption", "breach"],
  design:       ["design", "ux", "ui", "typography", "figma", "accessibility", "user experience"],
  crypto:       ["bitcoin", "ethereum", "blockchain", "cryptocurrency", "defi", "web3", "nft", "token"],
  space:        ["nasa", "spacex", "orbit", "satellite", "rocket", "astronaut", "mars", "telescope", "cosmos"],
  politics:     ["election", "congress", "senate", "president", "legislation", "policy", "democrat", "republican", "government"],
  health:       ["health", "medical", "vaccine", "clinical trial", "fda", "disease", "mental health", "therapy"],
  climate:      ["climate", "carbon", "renewable", "emissions", "sustainability", "solar", "wind energy", "fossil fuel"],
};

export async function main(event) {
  for (const record of event.Records) {
    const msg = JSON.parse(record.body);
    await extractArticle(msg);
  }
}

async function extractArticle({ urlHash, url, feedId, preExtract }) {
  if (!url) {
    console.warn("No URL in extraction message, skipping");
    return;
  }

  try {
    // Fetch page HTML
    const response = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(10_000),
      redirect: "follow",
    });

    if (!response.ok) {
      console.warn(`Fetch failed for ${url}: ${response.status}`);
      await fallbackToPuppeteer(urlHash, url);
      return;
    }

    const html = await response.text();

    // Parse with jsdom + Readability
    const dom = new JSDOM(html, { url });
    const reader = new Readability(dom.window.document);
    const article = reader.parse();

    if (!article || !article.title) {
      console.warn(`Readability failed for ${url} — no title`);
      await fallbackToPuppeteer(urlHash, url);
      return;
    }

    // Convert to ContentNode array
    const nodes = htmlToContentNodes(article.content || "");
    const wordCount = nodes
      .filter((n) => n.type === "paragraph" || n.type === "heading")
      .reduce((sum, n) => sum + (n.text?.split(/\s+/).length || 0), 0);

    if (wordCount < MIN_WORD_COUNT) {
      console.warn(`Thin content for ${url}: ${wordCount} words — falling back to Puppeteer`);
      await fallbackToPuppeteer(urlHash, url);
      return;
    }

    // Extract hero image (og:image)
    const heroImageURL = extractHeroImage(html);

    // Infer topics from title + content
    const topicTags = inferTopics(article.title, article.textContent || "");

    // Build extraction result
    const result = {
      title: article.title,
      author: article.byline || null,
      heroImageURL,
      nodes,
      cachedAt: new Date().toISOString(),
    };

    const s3Key = `articles/${urlHash}.json`;
    const body = JSON.stringify(result);

    // Store to S3 + index in DynamoDB
    await Promise.all([
      s3.send(
        new PutObjectCommand({
          Bucket: BUCKET,
          Key: s3Key,
          Body: body,
          ContentType: "application/json",
        })
      ),
      dynamo.send(
        new PutItemCommand({
          TableName: INDEX_TABLE,
          Item: {
            urlHash: { S: urlHash },
            s3Key: { S: s3Key },
            cachedAt: { S: result.cachedAt },
            extractedHost: { S: new URL(url).hostname },
            ttl: { N: String(Math.floor(Date.now() / 1000) + TTL_HOURS * 3600) },
          },
        })
      ),
    ]);

    // Enrich feed_items with extraction metadata
    if (feedId) {
      await query(
        `UPDATE feed_items SET word_count = $2, topic_tags = $3, extracted_at = NOW(), extraction_tier = 'jsdom'
         WHERE id = $1`,
        [feedId, wordCount, topicTags]
      ).catch(() => {}); // Non-critical — item may not exist if this was an on-demand extraction
    }

    console.log(`Extracted ${url} (jsdom): ${wordCount} words, topics: [${topicTags.join(", ")}]`);
  } catch (err) {
    console.error(`Extraction failed for ${url}:`, err.message);
    await fallbackToPuppeteer(urlHash, url);
  }
}

async function fallbackToPuppeteer(urlHash, url) {
  if (!PUPPETEER_QUEUE_URL) return;

  try {
    await sqs.send(
      new SendMessageCommand({
        QueueUrl: PUPPETEER_QUEUE_URL,
        MessageBody: JSON.stringify({ urlHash, url }),
        MessageDeduplicationId: urlHash,
        MessageGroupId: "extractions",
      })
    );
  } catch (err) {
    console.warn(`Puppeteer fallback enqueue failed for ${url}:`, err.message);
  }
}

// --- Topic Inference ---

function inferTopics(title, textContent) {
  const text = `${title} ${textContent.substring(0, 2000)}`.toLowerCase();
  const topics = [];

  for (const [topic, keywords] of Object.entries(TOPIC_KEYWORDS)) {
    if (keywords.some((kw) => text.includes(kw))) {
      topics.push(topic);
    }
  }

  return topics.slice(0, 5); // Cap at 5 topics per article
}

// --- HTML → ContentNode Conversion ---

function htmlToContentNodes(html) {
  const dom = new JSDOM(html);
  const doc = dom.window.document;
  const nodes = [];

  function walk(el) {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) {
        // Text node
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "paragraph", text });
        }
        continue;
      }

      if (child.nodeType !== 1) continue; // Skip non-element nodes

      const tag = child.tagName.toLowerCase();

      if (["h1", "h2", "h3", "h4", "h5", "h6"].includes(tag)) {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "heading", level: parseInt(tag[1]), text });
        }
      } else if (tag === "p") {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "paragraph", text });
        }
      } else if (tag === "img") {
        const src = child.getAttribute("src");
        if (src) {
          nodes.push({
            type: "image",
            url: src,
            caption: child.getAttribute("alt") || null,
          });
        }
      } else if (tag === "blockquote") {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "blockquote", text });
        }
      } else if (tag === "ul" || tag === "ol") {
        const items = Array.from(child.querySelectorAll("li")).map((li) => li.textContent.trim()).filter(Boolean);
        if (items.length > 0) {
          nodes.push({ type: "list", items, ordered: tag === "ol" });
        }
      } else if (tag === "pre" || tag === "code") {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "codeBlock", text });
        }
      } else if (tag === "figure") {
        const img = child.querySelector("img");
        const caption = child.querySelector("figcaption");
        if (img?.getAttribute("src")) {
          nodes.push({
            type: "image",
            url: img.getAttribute("src"),
            caption: caption?.textContent?.trim() || img.getAttribute("alt") || null,
          });
        } else {
          walk(child);
        }
      } else {
        // Recurse into divs, sections, articles, etc.
        walk(child);
      }
    }
  }

  walk(doc.body || doc);
  return nodes;
}

// --- Hero Image Extraction ---

function extractHeroImage(html) {
  // og:image meta tag
  const ogMatch = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i);
  if (ogMatch) return ogMatch[1];

  // Reverse attribute order
  const ogMatch2 = html.match(/<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']/i);
  if (ogMatch2) return ogMatch2[1];

  // twitter:image
  const twMatch = html.match(/<meta[^>]*name=["']twitter:image["'][^>]*content=["']([^"']+)["']/i);
  if (twMatch) return twMatch[1];

  return null;
}
