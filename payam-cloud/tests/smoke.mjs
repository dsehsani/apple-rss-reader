#!/usr/bin/env node
// Smoke tests for deployed Payam cloud endpoints.
// Validates that Lambdas are running and responding correctly.
//
// Usage:
//   API_URL=https://your-api-gateway-url node tests/smoke.mjs
//   API_URL=https://your-api-gateway-url JWT=your-jwt-token node tests/smoke.mjs

const API_URL = process.env.API_URL;
const JWT = process.env.JWT;

if (!API_URL) {
  console.error("Usage: API_URL=https://... node tests/smoke.mjs");
  console.error("       API_URL=https://... JWT=eyJ... node tests/smoke.mjs");
  process.exit(1);
}

const base = API_URL.replace(/\/+$/, "");
let passed = 0;
let failed = 0;

async function test(name, fn) {
  try {
    await fn();
    console.log(`  PASS  ${name}`);
    passed++;
  } catch (err) {
    console.error(`  FAIL  ${name}: ${err.message}`);
    failed++;
  }
}

function assert(condition, msg) {
  if (!condition) throw new Error(msg);
}

function authHeaders() {
  if (!JWT) return {};
  return { Authorization: `Bearer ${JWT}` };
}

console.log(`\nSmoke testing: ${base}\n`);

// --- Unauthenticated Tests ---

await test("POST /v1/auth/apple returns 400 with empty body (not 500)", async () => {
  const r = await fetch(`${base}/v1/auth/apple`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });
  assert(r.status === 400, `Expected 400, got ${r.status}`);
  const body = await r.json();
  assert(body.error, "Should have error message");
});

await test("GET /v1/river without auth returns 401", async () => {
  const r = await fetch(`${base}/v1/river`);
  assert(r.status === 401, `Expected 401, got ${r.status}`);
});

await test("POST /v1/state without auth returns 401", async () => {
  const r = await fetch(`${base}/v1/state`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });
  assert(r.status === 401, `Expected 401, got ${r.status}`);
});

await test("POST /v1/discover without auth returns 401", async () => {
  const r = await fetch(`${base}/v1/discover`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query: "tech" }),
  });
  assert(r.status === 401, `Expected 401, got ${r.status}`);
});

// --- Authenticated Tests (require JWT) ---

if (JWT) {
  console.log("\n  Running authenticated tests...\n");

  await test("GET /v1/river returns 200 with items array", async () => {
    const r = await fetch(`${base}/v1/river?since=0&limit=5`, {
      headers: authHeaders(),
    });
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    const body = await r.json();
    assert(Array.isArray(body.items), "Should have items array");
    assert(typeof body.syncToken === "string", "Should have syncToken");
    assert(typeof body.hasMore === "boolean", "Should have hasMore");
  });

  await test("POST /v1/state accepts valid state payload", async () => {
    const r = await fetch(`${base}/v1/state`, {
      method: "POST",
      headers: { ...authHeaders(), "Content-Type": "application/json" },
      body: JSON.stringify({ states: [] }), // Empty batch is valid
    });
    assert(r.status === 204 || r.status === 200, `Expected 204 or 200, got ${r.status}`);
  });

  await test("POST /v1/discover returns results for 'tech'", async () => {
    const r = await fetch(`${base}/v1/discover`, {
      method: "POST",
      headers: { ...authHeaders(), "Content-Type": "application/json" },
      body: JSON.stringify({
        query: "technology",
        subscribedURLs: [],
        topicAffinities: { technology: 0.8 },
        limit: 5,
      }),
    });
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    const body = await r.json();
    assert(Array.isArray(body.feeds), "Should have feeds array");
    assert(typeof body.total === "number", "Should have total count");
  });

  await test("POST /v1/discover rejects empty query", async () => {
    const r = await fetch(`${base}/v1/discover`, {
      method: "POST",
      headers: { ...authHeaders(), "Content-Type": "application/json" },
      body: JSON.stringify({ query: "" }),
    });
    assert(r.status === 400, `Expected 400, got ${r.status}`);
  });

  await test("GET /v1/extract/{hash} returns 202 or 200 for a known URL", async () => {
    const url = "https://example.com/test-article";
    const hash = await crypto.subtle
      .digest("SHA-256", new TextEncoder().encode(url))
      .then((buf) =>
        Array.from(new Uint8Array(buf))
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("")
      );

    const r = await fetch(`${base}/v1/extract/${hash}?url=${encodeURIComponent(url)}`, {
      headers: authHeaders(),
    });
    // 200 = cache hit, 202 = queued for extraction, both are valid
    assert(
      [200, 202].includes(r.status),
      `Expected 200 or 202, got ${r.status}`
    );
  });
} else {
  console.log("\n  Skipping authenticated tests (no JWT provided)\n");
  console.log("  To run authenticated tests:");
  console.log("    API_URL=https://... JWT=eyJ... node tests/smoke.mjs\n");
}

// --- Summary ---
console.log(`\n  Results: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
