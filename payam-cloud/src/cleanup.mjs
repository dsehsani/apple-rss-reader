// Scheduled Lambda — runs daily to delete feed_items older than 30 days.
// Also cleans up orphaned user_item_state rows referencing deleted items.

import { query } from "./db.mjs";

export async function main() {
  const itemResult = await query(
    `DELETE FROM feed_items WHERE fetched_at < NOW() - INTERVAL '30 days' RETURNING id`
  );

  const deletedCount = itemResult.rowCount;

  if (deletedCount > 0) {
    // Clean up orphaned state rows
    const stateResult = await query(
      `DELETE FROM user_item_state
       WHERE item_id NOT IN (SELECT id FROM feed_items)`
    );
    console.log(
      `Cleanup: deleted ${deletedCount} old feed_items, ${stateResult.rowCount} orphaned state rows`
    );
  } else {
    console.log("Cleanup: no items older than 30 days");
  }
}
