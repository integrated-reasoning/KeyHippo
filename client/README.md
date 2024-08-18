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

// Get information about an API key
const keyInfo = await keyHippo.loadApiKeyInfo(apiKeyId);

// Get all API keys for a user
const allKeys = await keyHippo.getAllKeyMetadata(userId);
```

## Documentation

For complete documentation, including detailed API references and advanced usage, please refer to our [main documentation](/docs/API-Reference.md).

## Contributing

We welcome contributions! Please see our [Contributing Guide](/docs/Contributing.md) for more information.

## License

This package is part of the KeyHippo project and is distributed under the MIT license. See the [LICENSE](../LICENSE) file for details.
