// GET /v1/extract/{urlHash}
// Checks DynamoDB extraction-index for a cached article.
// On hit: returns ContentNode JSON from S3.
// On miss: enqueues URL for server-side extraction, returns 404.

import { DynamoDBClient, GetItemCommand } from "@aws-sdk/client-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { requireAuth } from "./jwt.mjs";

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const sqs = new SQSClient({});

const INDEX_TABLE = process.env.EXTRACTION_INDEX_TABLE || "payam-extraction-index";
const BUCKET = process.env.EXTRACTION_BUCKET || "payam-extractions";
const LIGHT_QUEUE_URL = process.env.EXTRACTION_LIGHT_QUEUE_URL;
const PUPPETEER_QUEUE_URL = process.env.EXTRACTION_QUEUE_URL;

async function handler(event) {
  const urlHash = event.pathParameters?.hash;
  const articleUrl = event.queryStringParameters?.url;
  if (!urlHash) {
    return respond(400, { error: "URL hash required" });
  }

  // Check DynamoDB index
  const indexResult = await dynamo.send(
    new GetItemCommand({
      TableName: INDEX_TABLE,
      Key: { urlHash: { S: urlHash } },
    })
  );

  if (indexResult.Item?.s3Key?.S) {
    // Cache hit — fetch from S3
    try {
      const s3Result = await s3.send(
        new GetObjectCommand({
          Bucket: BUCKET,
          Key: indexResult.Item.s3Key.S,
        })
      );

      const body = await s3Result.Body.transformToString();
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body,
      };
    } catch (err) {
      console.error("S3 fetch failed:", err.message);
      // Fall through to miss
    }
  }

  // Cache miss — enqueue for lightweight extraction first (jsdom),
  // which falls back to Puppeteer if content is thin or JS-rendered.
  const queueUrl = LIGHT_QUEUE_URL || PUPPETEER_QUEUE_URL;
  if (queueUrl) {
    try {
      const messageParams = {
        QueueUrl: queueUrl,
        MessageBody: JSON.stringify({ urlHash, url: articleUrl }),
      };
      // FIFO queue requires dedup/group IDs
      if (queueUrl.endsWith(".fifo")) {
        messageParams.MessageDeduplicationId = urlHash;
        messageParams.MessageGroupId = "extractions";
      }
      await sqs.send(new SendMessageCommand(messageParams));
    } catch {
      // Non-critical — extraction will happen on next request
    }
  }

  return respond(202, { status: "queued", retryAfterSeconds: 5 });
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

export const main = requireAuth(handler, process.env.JWT_SECRET);
