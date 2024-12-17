# create_api_key

Creates a new API key for the authenticated user.

## Syntax

```sql
keyhippo.create_api_key(
    key_description text,
    scope_name text DEFAULT NULL
) RETURNS TABLE (
    api_key text,
    api_key_id uuid
)
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| key_description | text | Description of the API key. Must be 255 characters or less and contain only alphanumeric characters, spaces, underscores, and hyphens. |
| scope_name | text | (Optional) Name of the scope to assign to the key. Must match an existing scope in the `keyhippo.scopes` table. |

## Returns

Returns a table with two columns:
- `api_key` (text): The complete API key (prefix + key hash). This is the only time the full key will be available.
- `api_key_id` (uuid): The unique identifier for the created API key.

## Security

- SECURITY DEFINER function
- Requires authenticated user context
- Creates records in both `api_key_metadata` and `api_key_secrets` tables
- Only authenticated users can execute

## Example Usage

```sql
-- Create an API key with default scope
SELECT * FROM keyhippo.create_api_key('Production API Key');

-- Create an API key with specific scope
SELECT * FROM keyhippo.create_api_key('Analytics API', 'analytics');
```

## Notes

- The API key is generated using cryptographically secure random bytes
- Only the hash of the key is stored in the database
- The prefix is used for quick lookups without exposing the full key
- Key creation is logged in the audit system
- Keys do not expire by default (100 year expiration)

## Related

- [verify_api_key()](verify_api_key.md)
- [revoke_api_key()](revoke_api_key.md)
- [rotate_api_key()](rotate_api_key.md)
- [api_key_metadata table](../tables/api_key_metadata.md)