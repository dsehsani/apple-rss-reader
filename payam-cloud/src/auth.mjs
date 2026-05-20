// POST /v1/auth/apple
// Verifies Apple identity token and returns a Payam JWT.

import crypto from "node:crypto";
import { sign } from "./jwt.mjs";
import { DynamoDBClient, GetItemCommand, PutItemCommand } from "@aws-sdk/client-dynamodb";

const dynamo = new DynamoDBClient({});
const USERS_TABLE = process.env.USERS_TABLE || "payam-users";

export async function main(event) {
  try {
    const body = JSON.parse(event.body || "{}");
    const { identityToken, appleUserID } = body;

    if (!identityToken || !appleUserID) {
      return respond(400, { error: "identityToken and appleUserID are required" });
    }

    // Verify Apple identity token
    const applePayload = await verifyAppleToken(identityToken);
    if (applePayload.sub !== appleUserID) {
      return respond(401, { error: "Apple user ID mismatch" });
    }

    // Get or create user in DynamoDB
    const user = await getOrCreateUser(appleUserID);

    // Sign JWT
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      return respond(500, { error: "JWT secret not configured" });
    }

    const expiresIn = 86400; // 24 hours
    const jwt = sign(
      { sub: appleUserID, tier: user.tier },
      jwtSecret,
      expiresIn
    );

    const now = Math.floor(Date.now() / 1000);

    return respond(200, {
      jwt,
      expiresAt: now + expiresIn,
      tier: user.tier,
      tierExpiresAt: user.tierExpiresAt || null,
      quotas: {
        agentCallsRemaining: user.agentCallsRemaining ?? 5,
        agentCallsResetAt: user.agentCallsResetAt || null,
      },
    });
  } catch (err) {
    console.error("Auth error:", err);
    return respond(500, { error: "Authentication failed" });
  }
}

// Verify Apple identity token by fetching Apple's public keys
async function verifyAppleToken(identityToken) {
  // Decode without verification first to get the key ID
  const parts = identityToken.split(".");
  if (parts.length !== 3) throw new Error("Invalid Apple token format");

  const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
  const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());

  // Fetch Apple's public keys
  const keysResponse = await fetch("https://appleid.apple.com/auth/keys");
  const { keys } = await keysResponse.json();
  const key = keys.find((k) => k.kid === header.kid);
  if (!key) throw new Error("Apple signing key not found");

  // Build public key and verify signature
  const publicKey = crypto.createPublicKey({ key, format: "jwk" });
  const data = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], "base64url");
  const alg = header.alg === "ES256" ? "SHA256" : "SHA256";

  const valid = crypto.verify(alg, data, publicKey, signature);
  if (!valid) throw new Error("Invalid Apple token signature");

  // Verify claims
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) throw new Error("Apple token expired");
  if (payload.iss !== "https://appleid.apple.com") throw new Error("Invalid issuer");

  return payload;
}

async function getOrCreateUser(appleUserID) {
  const result = await dynamo.send(
    new GetItemCommand({
      TableName: USERS_TABLE,
      Key: { userId: { S: appleUserID } },
    })
  );

  if (result.Item) {
    return {
      tier: result.Item.tier?.S || "free",
      tierExpiresAt: result.Item.tierExpiresAt?.N ? parseInt(result.Item.tierExpiresAt.N) : null,
      agentCallsRemaining: result.Item.agentCallsRemaining?.N
        ? parseInt(result.Item.agentCallsRemaining.N)
        : 5,
      agentCallsResetAt: result.Item.agentCallsResetAt?.S || null,
    };
  }

  // Create new free user
  await dynamo.send(
    new PutItemCommand({
      TableName: USERS_TABLE,
      Item: {
        userId: { S: appleUserID },
        tier: { S: "free" },
        createdAt: { N: String(Math.floor(Date.now() / 1000)) },
        agentCallsRemaining: { N: "5" },
      },
    })
  );

  return { tier: "free", tierExpiresAt: null, agentCallsRemaining: 5, agentCallsResetAt: null };
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
