# KeyHippo Client

This package provides the client-side implementation for KeyHippo, enabling seamless API key management in Supabase applications.

## Installation

```bash
npm install keyhippo
```

## Basic Usage

```typescript
import { KeyHippo } from "keyhippo";

// Initialize KeyHippo with your Supabase client
const keyHippo = new KeyHippo(supabaseClient);

// Create a new API key
const result = await keyHippo.createApiKey(userId, "Primary API Key");

// Revoke an API key
await keyHippo.revokeApiKey(apiKeyId);

// Load all API keys' information for a specific user
const keyInfos = await keyHippo.loadApiKeyInfo(userId);
// Returns an array of `ApiKeyInfo` objects containing basic details about each API key associated with the user,
// such as the key's ID and description. If no keys are found, an empty array is returned.

// Get metadata for all API keys associated with a user
const metadata = await keyHippo.getAllKeyMetadata(userId);
// Returns an array of `ApiKeyMetadata` objects, which include detailed metadata for each API key,
// such as usage statistics, creation date, and revocation status. If no keys are found, an empty array is returned.
```

## Documentation

For complete documentation, including detailed API references and advanced usage, please refer to our [main documentation](/docs/API-Reference.md).

## Contributing

We welcome contributions! Please see our [Contributing Guide](/docs/Contributing.md) for more information.

## License

This package is part of the KeyHippo project and is distributed under the MIT license. See the [LICENSE](../LICENSE) file for details.
