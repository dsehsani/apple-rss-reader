// POST /v1/state
// Syncs read/bookmark state from device to cloud.

import { getPool } from "./db.mjs";
import { requireAuth } from "./jwt.mjs";

async function handler(event) {
  const userId = event.auth.sub;
  const body = JSON.parse(event.body || "{}");
  const states = body.states;

  if (!Array.isArray(states) || states.length === 0) {
    return { statusCode: 400, body: JSON.stringify({ error: "states array required" }) };
  }

  // Batch upsert using unnest for efficiency, wrapped in a transaction
  const itemIds = states.map((s) => s.itemID);
  const reads = states.map((s) => s.isRead ?? false);
  const bookmarks = states.map((s) => s.isBookmarked ?? false);

  const pool = await getPool();
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      `INSERT INTO user_item_state (user_id, item_id, is_read, is_bookmarked, updated_at)
       SELECT $1, unnest($2::uuid[]), unnest($3::boolean[]), unnest($4::boolean[]), NOW()
       ON CONFLICT (user_id, item_id)
       DO UPDATE SET
         is_read = EXCLUDED.is_read,
         is_bookmarked = EXCLUDED.is_bookmarked,
         updated_at = NOW()`,
      [userId, itemIds, reads, bookmarks]
    );
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }

  return { statusCode: 204, body: "" };
}

export const main = requireAuth(handler);
