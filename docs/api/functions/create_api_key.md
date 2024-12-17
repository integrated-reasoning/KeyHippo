# create_api_key

Generate a new API key for an authenticated user.

## Synopsis

```sql
keyhippo.create_api_key(
    key_description text,
    scope_name text DEFAULT NULL
) RETURNS TABLE (
    api_key text,
    api_key_id uuid
)
```

## Description

`create_api_key` generates an API key in the format: `prefix_string.key_string` where:
- `prefix_string` is an 8-character base32 string used for key lookups
- `key_string` is a 32-character base32 string used for authentication

The function stores:
- A SHA-256 hash of the key in `api_key_secrets`
- Key metadata in `api_key_metadata` including creation time, description, and scope
- An audit log entry with the key ID and creating user

## Parameters

| Name | Type | Description |
|------|------|-------------|
| key_description | text | Identifier for the key. Maximum 255 characters. Accepts alphanumeric characters, spaces, underscores, and hyphens. |
| scope_name | text | Optional. References a scope in `keyhippo.scopes`. NULL means default scope. |

## Return Value

Returns a table with:
- `api_key`: Full key string in format `prefix_string.key_string`. Only returned at creation.
- `api_key_id`: UUID for referencing the key in other operations.

## Privileges Required

- User must be authenticated
- Function runs with SECURITY DEFINER
- No additional privileges needed

## Examples

Create a key with default scope:
```sql
SELECT * FROM keyhippo.create_api_key('Production API');
-- Returns:
--           api_key           |              api_key_id
-- ----------------------------+--------------------------------------
-- KH2ABJM1.NBTGK19FH27DJSM4 | 550e8400-e29b-41d4-a716-446655440000
```

Create a key with analytics scope:
```sql
SELECT * FROM keyhippo.create_api_key('Analytics Key', 'analytics');
```

## Implementation

1. Generates 30 random bytes using `gen_random_bytes(30)`
2. Encodes bytes as base32 to create key_string
3. Takes first 5 bytes for prefix_string
4. Computes SHA-256 hash of the complete key
5. Stores hash and metadata with timestamp
6. Records audit log entry with key_id and user_id
7. Returns assembled key with prefix

Default key settings:
- Expiration: 100 years from creation
- Status: active
- Hash algorithm: SHA-256
- Key format version: 1

## See Also

- [verify_api_key()](verify_api_key.md) - Validation algorithm
- [revoke_api_key()](revoke_api_key.md) - Key invalidation
- [rotate_api_key()](rotate_api_key.md) - Key replacement
- [api_key_metadata](../tables/api_key_metadata.md) - Metadata storage