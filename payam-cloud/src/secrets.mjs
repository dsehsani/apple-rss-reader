// AWS Secrets Manager loader with Lambda cold-start caching.
// Reads a single JSON secret containing DB_PASSWORD and JWT_SECRET.
// Warm invocations reuse the cached value.

import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({});
const SECRET_ARN = process.env.SECRETS_ARN;

let cached = null;

export async function getSecrets() {
  if (cached) return cached;

  // Fall back to env vars when SECRETS_ARN is not set (local dev)
  if (!SECRET_ARN) {
    cached = {
      DB_PASSWORD: process.env.DB_PASSWORD || "",
      JWT_SECRET: process.env.JWT_SECRET || "",
    };
    return cached;
  }

  const result = await client.send(
    new GetSecretValueCommand({ SecretId: SECRET_ARN })
  );
  cached = JSON.parse(result.SecretString);
  return cached;
}

export async function getDBPassword() {
  return (await getSecrets()).DB_PASSWORD;
}

export async function getJWTSecret() {
  return (await getSecrets()).JWT_SECRET;
}
