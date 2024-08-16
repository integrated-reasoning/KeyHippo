# KeyHippo

KeyHippo extends Supabase's Row Level Security (RLS) framework, enabling seamless integration of API key authentication within existing security policies.

## Core Functionality

KeyHippo addresses the challenge of incorporating API key authentication in Supabase applications without compromising the integrity of Row Level Security. It achieves this by extending the RLS framework to encompass both session-based and API key authentication methods within a unified security context. This approach eliminates the need for parallel security structures and maintains granular access control across authentication types.

Key aspects:
- Unified RLS policies supporting dual authentication methods
- SQL-based API key issuance
- Preservation of existing Supabase RLS implementations
- Essential API key lifecycle management

## Implementation

### Database Setup

1. Install the KeyHippo extension:

   ```sql
   select dbdev.install('keyhippo@keyhippo');
   create extension "keyhippo@keyhippo"
       version '0.0.5';
   ```

   Consult [database.dev](https://database.dev/keyhippo/keyhippo) for version updates.

2. Post-installation, KeyHippo functions become accessible within your database environment.

### Application Integration

Install via npm:

```bash
npm install keyhippo
```

## Usage Paradigms

### API Key Generation

```typescript
import { KeyHippo } from 'keyhippo';

const keyHippo = new KeyHippo(supabaseClient);
const result = await keyHippo.createApiKey(userId, 'Primary API Key');
```

### RLS Policy Implementation

Example of a policy supporting dual authentication:

```sql
CREATE POLICY "owner_access"
ON "public"."resource_table"
USING (
  auth.uid() = resource_table.owner_id
  OR auth.keyhippo_check(resource_table.owner_id)
);
```

This policy grants access when the user is authenticated via a session token (`auth.uid()`) or a valid API key associated with the resource owner (`auth.keyhippo_check()`).

### Additional Functionality

- `revokeApiKey`: Invalidate an existing API key
- `loadApiKeyInfo`: Retrieve metadata for existing keys
- `getAllKeyMetadata`: Comprehensive metadata for a user's API keys

## Alpha Status

KeyHippo is currently in alpha status. We adhere to semantic versioning, and as such, KeyHippo will remain in alpha (versions < 0.1.0) until we've thoroughly validated its stability and feature completeness in production environments. During this phase, we welcome early adopters to provide feedback and report issues.

## Origins and Evolution

KeyHippo emerged from a pattern observed across Integrated Reasoning's Supabase projects: the need to reconcile API key authentication with Row Level Security policies. This challenge, also noted in Supabase's GitHub discussions (#4419), highlighted a gap in existing solutions.
We developed KeyHippo to address this, drawing insights from community discussions and approaches, including work by GitHub user j4w8n. The result is a streamlined, production-ready system for API key management in Supabase applications.

## Contribution

KeyHippo welcomes community contributions. For guidance on contributing, please refer to our [Contributing Guide](CONTRIBUTING.md).

## Licensing

KeyHippo is distributed under the MIT license.

## Support Channels

For technical issues, feature requests, or general inquiries, please open an issue on our [GitHub repository](https://github.com/integrated-reasoning/KeyHippo/issues).

For commercial support options, consult [keyhippo.com](https://keyhippo.com).
