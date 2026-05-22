// Database connection pool for PostgreSQL (RDS).
// Reuses connections across Lambda invocations within the same container.

import pg from "pg";
import { getDBPassword } from "./secrets.mjs";

let pool = null;
let poolReady = null;

async function initPool() {
  const password = await getDBPassword();
  pool = new pg.Pool({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || "5432"),
    database: process.env.DB_NAME || "payam",
    user: process.env.DB_USER || "payam",
    password,
    max: 3, // Lambda containers are single-threaded; keep pool small
    idleTimeoutMillis: 60_000,
    connectionTimeoutMillis: 5_000,
    ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false },
  });
  return pool;
}

export function getPool() {
  if (!poolReady) {
    poolReady = initPool();
  }
  return poolReady;
}

export async function query(text, params) {
  const p = await getPool();
  const client = await p.connect();
  try {
    return await client.query(text, params);
  } finally {
    client.release();
  }
}
