// SSRF protection — validates URLs before fetching.
// Blocks private/reserved IP ranges and non-HTTP schemes.

const BLOCKED_RANGES = [
  /^127\./,                          // loopback
  /^10\./,                           // RFC 1918
  /^172\.(1[6-9]|2\d|3[01])\./,     // RFC 1918
  /^192\.168\./,                     // RFC 1918
  /^169\.254\./,                     // link-local
  /^0\./,                            // "this" network
  /^100\.(6[4-9]|[7-9]\d|1[0-2]\d)\./, // carrier-grade NAT
  /^::1$/,                           // IPv6 loopback
  /^fd[0-9a-f]{2}:/i,               // IPv6 ULA
  /^fe80:/i,                         // IPv6 link-local
];

/**
 * Throws if the URL is not safe to fetch (non-HTTP scheme or resolves
 * to a private/reserved IP range). Call before any outbound fetch.
 */
export function assertSafeURL(raw) {
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`Invalid URL: ${raw}`);
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`Blocked scheme: ${parsed.protocol}`);
  }

  // Block if the hostname is a raw IP in a private range
  const host = parsed.hostname;
  if (BLOCKED_RANGES.some((re) => re.test(host))) {
    throw new Error(`Blocked private/reserved IP: ${host}`);
  }

  // Block localhost variants
  if (host === "localhost" || host === "[::1]") {
    throw new Error(`Blocked localhost: ${host}`);
  }

  return parsed;
}
