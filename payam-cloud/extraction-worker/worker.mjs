// ECS Fargate Extraction Worker
// Polls SQS for article URLs, extracts content via Puppeteer + Readability,
// stores ContentNode JSON in S3, indexes in DynamoDB.

import puppeteer from "puppeteer";
import { Readability } from "@mozilla/readability";
import { JSDOM } from "jsdom";
import crypto from "node:crypto";
import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand,
} from "@aws-sdk/client-sqs";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import {
  DynamoDBClient,
  PutItemCommand,
  GetItemCommand,
} from "@aws-sdk/client-dynamodb";

const sqs = new SQSClient({});
const s3 = new S3Client({});
const dynamo = new DynamoDBClient({});

const QUEUE_URL = process.env.EXTRACTION_QUEUE_URL;
const BUCKET = process.env.EXTRACTION_BUCKET || "payam-extractions-dev";
const INDEX_TABLE =
  process.env.EXTRACTION_INDEX_TABLE || "payam-extraction-index-dev";

let browser = null;

async function getBrowser() {
  if (!browser) {
    browser = await puppeteer.launch({
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--single-process",
      ],
    });
    console.log("Browser launched");
  }
  return browser;
}

// Convert Readability HTML output to ContentNode array
function htmlToContentNodes(html) {
  const dom = new JSDOM(html);
  const doc = dom.window.document;
  const nodes = [];

  function walk(element) {
    for (const child of element.children) {
      const tag = child.tagName.toLowerCase();

      if (["script", "style", "noscript"].includes(tag)) continue;

      if (["h1", "h2", "h3", "h4", "h5", "h6"].includes(tag)) {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({
            type: "heading",
            level: parseInt(tag[1]),
            text,
          });
        }
      } else if (tag === "p") {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "paragraph", text });
        }
      } else if (tag === "img") {
        const src = child.getAttribute("src");
        if (src && src.startsWith("http")) {
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
        const items = Array.from(child.querySelectorAll("li")).map((li) =>
          li.textContent.trim()
        );
        if (items.length > 0) {
          nodes.push({
            type: "list",
            items,
            ordered: tag === "ol",
          });
        }
      } else if (tag === "pre") {
        const text = child.textContent.trim();
        if (text) {
          nodes.push({ type: "codeBlock", text });
        }
      } else if (tag === "figure") {
        const img = child.querySelector("img");
        const caption = child.querySelector("figcaption");
        if (img?.src?.startsWith("http")) {
          nodes.push({
            type: "image",
            url: img.src,
            caption: caption?.textContent?.trim() || null,
          });
        }
        // Also walk for non-image content inside figures
      } else if (tag === "table") {
        const headers = Array.from(child.querySelectorAll("th")).map((th) =>
          th.textContent.trim()
        );
        const rows = Array.from(child.querySelectorAll("tr"))
          .map((tr) =>
            Array.from(tr.querySelectorAll("td")).map((td) =>
              td.textContent.trim()
            )
          )
          .filter((r) => r.length > 0);
        if (rows.length > 0) {
          nodes.push({ type: "table", headers, rows });
        }
      } else if (tag === "iframe") {
        const src = child.getAttribute("src") || "";
        if (
          src.includes("youtube") ||
          src.includes("vimeo") ||
          src.includes("dailymotion")
        ) {
          nodes.push({ type: "videoEmbed", url: src, thumbnailURL: null });
        }
      } else {
        // Recurse into divs, sections, articles, etc.
        walk(child);
      }
    }
  }

  walk(doc.body);
  return nodes;
}

async function extractArticle(url) {
  const b = await getBrowser();
  const page = await b.newPage();

  try {
    await page.setUserAgent(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    );
    await page.setViewport({ width: 1280, height: 900 });

    // Some sites block if no accept headers are set
    await page.setExtraHTTPHeaders({
      "Accept-Language": "en-US,en;q=0.9",
    });

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });

    // Wait for JS to settle
    await new Promise((r) => setTimeout(r, 2000));

    const html = await page.content();
    const dom = new JSDOM(html, { url });
    const reader = new Readability(dom.window.document);
    const article = reader.parse();

    if (!article || !article.content) {
      throw new Error("Readability failed to parse article");
    }

    // Extract hero image from og:image meta tag
    const ogImage = await page
      .$eval('meta[property="og:image"]', (el) => el.content)
      .catch(() => null);

    const nodes = htmlToContentNodes(article.content);

    return {
      title: article.title || "",
      author: article.byline || null,
      heroImageURL: ogImage,
      nodes,
      cachedAt: new Date().toISOString(),
    };
  } finally {
    await page.close();
  }
}

async function processMessage(message) {
  const { urlHash, url } = JSON.parse(message.Body);

  // Check if already cached
  const existing = await dynamo.send(
    new GetItemCommand({
      TableName: INDEX_TABLE,
      Key: { urlHash: { S: urlHash } },
    })
  );

  if (existing.Item?.s3Key?.S) {
    console.log(`Already cached: ${urlHash}`);
    return;
  }

  console.log(`Extracting: ${url}`);
  const result = await extractArticle(url);

  // Store in S3
  const s3Key = `articles/${urlHash}.json`;
  await s3.send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: s3Key,
      Body: JSON.stringify(result),
      ContentType: "application/json",
    })
  );

  // Index in DynamoDB
  const ttl = Math.floor(Date.now() / 1000) + 72 * 3600; // 72 hours
  await dynamo.send(
    new PutItemCommand({
      TableName: INDEX_TABLE,
      Item: {
        urlHash: { S: urlHash },
        s3Key: { S: s3Key },
        cachedAt: { S: new Date().toISOString() },
        ttl: { N: String(ttl) },
      },
    })
  );

  console.log(`Cached: ${urlHash} → ${s3Key}`);
}

// Main polling loop
async function main() {
  console.log(`Extraction worker started. Queue: ${QUEUE_URL}`);

  // Keep browser warm
  await getBrowser();

  while (true) {
    try {
      const result = await sqs.send(
        new ReceiveMessageCommand({
          QueueUrl: QUEUE_URL,
          MaxNumberOfMessages: 1,
          WaitTimeSeconds: 20, // Long polling
        })
      );

      if (!result.Messages || result.Messages.length === 0) {
        continue;
      }

      for (const message of result.Messages) {
        try {
          await processMessage(message);
        } catch (err) {
          console.error(`Extraction failed: ${err.message}`);
        }

        // Delete from queue regardless (don't retry failed extractions endlessly)
        await sqs.send(
          new DeleteMessageCommand({
            QueueUrl: QUEUE_URL,
            ReceiptHandle: message.ReceiptHandle,
          })
        );
      }
    } catch (err) {
      console.error(`Poll error: ${err.message}`);
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

main().catch(console.error);
