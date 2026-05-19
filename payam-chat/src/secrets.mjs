import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const ANTHROPIC_SECRET_ID = 'openrss/anthropic-api-key';

const client = new SecretsManagerClient({});
let cached = null;

function parseKey(secretString) {
  const trimmed = secretString.trim();
  if (!trimmed.startsWith('{')) return trimmed;
  try {
    const obj = JSON.parse(trimmed);
    return (
      obj.ANTHROPIC_API_KEY?.trim() ||
      obj.apiKey?.trim() ||
      Object.values(obj).find((v) => typeof v === 'string' && v.trim().length > 0)?.trim() ||
      trimmed
    );
  } catch {
    return trimmed;
  }
}

export async function getAnthropicApiKey() {
  if (cached) return cached;
  const out = await client.send(new GetSecretValueCommand({ SecretId: ANTHROPIC_SECRET_ID }));
  if (!out.SecretString) throw new Error('Anthropic secret missing SecretString');
  const key = parseKey(out.SecretString);
  if (!key) throw new Error('Could not parse Anthropic API key from secret');
  cached = key;
  return key;
}
