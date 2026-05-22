// POST /v1/devices/register
// Stores APNs device token for silent push notifications.

import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { requireAuth } from "./jwt.mjs";

const dynamo = new DynamoDBClient({});
const TABLE = process.env.DEVICE_TOKENS_TABLE || "payam-device-tokens";

async function handler(event) {
  const userId = event.auth.sub;
  const body = JSON.parse(event.body || "{}");
  const { deviceToken, bundleID } = body;

  if (!deviceToken) {
    return { statusCode: 400, body: JSON.stringify({ error: "deviceToken required" }) };
  }

  await dynamo.send(
    new PutItemCommand({
      TableName: TABLE,
      Item: {
        userId: { S: userId },
        deviceToken: { S: deviceToken },
        bundleID: { S: bundleID || "com.payam" },
        registeredAt: { N: String(Math.floor(Date.now() / 1000)) },
      },
    })
  );

  return { statusCode: 204, body: "" };
}

export const main = requireAuth(handler);
