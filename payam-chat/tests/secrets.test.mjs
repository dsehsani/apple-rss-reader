import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import esmock from 'esmock';

describe('secrets', () => {
  describe('getAnthropicApiKey', () => {
    it('returns the secret string when it is a plain key', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return { SecretString: 'sk-ant-abc123' };
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      const key = await getAnthropicApiKey();
      assert.equal(key, 'sk-ant-abc123');
    });

    it('parses ANTHROPIC_API_KEY from a JSON secret', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return { SecretString: JSON.stringify({ ANTHROPIC_API_KEY: 'sk-from-json' }) };
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      const key = await getAnthropicApiKey();
      assert.equal(key, 'sk-from-json');
    });

    it('parses apiKey field from a JSON secret', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return { SecretString: JSON.stringify({ apiKey: 'sk-apikey-field' }) };
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      const key = await getAnthropicApiKey();
      assert.equal(key, 'sk-apikey-field');
    });

    it('falls back to first string value in JSON secret', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return { SecretString: JSON.stringify({ someOtherKey: 'sk-fallback' }) };
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      const key = await getAnthropicApiKey();
      assert.equal(key, 'sk-fallback');
    });

    it('throws when SecretString is missing', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return {};
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      await assert.rejects(getAnthropicApiKey(), /Anthropic secret missing SecretString/);
    });

    it('returns raw trimmed string for invalid JSON that starts with {', async () => {
      const { getAnthropicApiKey } = await esmock('../src/secrets.mjs', {
        '@aws-sdk/client-secrets-manager': {
          SecretsManagerClient: class {
            send() {
              return { SecretString: '{not-valid-json' };
            }
          },
          GetSecretValueCommand: class {
            constructor(params) { this.params = params; }
          },
        },
      });
      const key = await getAnthropicApiKey();
      assert.equal(key, '{not-valid-json');
    });
  });
});
