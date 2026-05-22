// Minimal JWT (HS256) implementation for Payam auth.
// No external dependency — uses Node's built-in crypto module.

import crypto from "node:crypto";
import { getJWTSecret } from "./secrets.mjs";

const ALG = "HS256";
const HEADER = Buffer.from(JSON.stringify({ alg: ALG, typ: "JWT" })).toString("base64url");

export function sign(payload, secret, expiresInSeconds = 86400) {
  const now = Math.floor(Date.now() / 1000);
  const claims = { ...payload, iat: now, exp: now + expiresInSeconds };
  const body = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signature = crypto
    .createHmac("sha256", secret)
    .update(`${HEADER}.${body}`)
    .digest("base64url");
  return `${HEADER}.${body}.${signature}`;
}

export function verify(token, secret) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Invalid JWT format");

  const [header, body, signature] = parts;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");

  if (signature !== expected) throw new Error("Invalid JWT signature");

  const payload = JSON.parse(Buffer.from(body, "base64url").toString());
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) throw new Error("JWT expired");

  return payload;
}

// Middleware: extracts and verifies JWT from Authorization header.
// Attaches payload to event.auth. Returns 401 response on failure.
// Secret is loaded from Secrets Manager (cached after cold start).
export function requireAuth(handler) {
  return async (event) => {
    const authHeader = event.headers?.authorization || event.headers?.Authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      return { statusCode: 401, body: JSON.stringify({ error: "Missing authorization" }) };
    }

    try {
      const secret = await getJWTSecret();
      event.auth = verify(authHeader.slice(7), secret);
    } catch (err) {
      return { statusCode: 401, body: JSON.stringify({ error: err.message }) };
    }

    return handler(event);
  };
}
