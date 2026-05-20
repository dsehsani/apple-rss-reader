// Database connection pool for PostgreSQL (RDS).
// Reuses connections across Lambda invocations within the same container.

import pg from "pg";

let pool = null;

export function getPool() {
  if (!pool) {
    pool = new pg.Pool({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || "5432"),
      database: process.env.DB_NAME || "payam",
      user: process.env.DB_USER || "payam",
      password: process.env.DB_PASSWORD,
      max: 3, // Lambda containers are single-threaded; keep pool small
      idleTimeoutMillis: 60_000,
      connectionTimeoutMillis: 5_000,
      ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false },
    });
  }
  return pool;
}

export async function query(text, params) {
  const client = await getPool().connect();
  try {
    return await client.query(text, params);
  } finally {
    client.release();
  }
}
