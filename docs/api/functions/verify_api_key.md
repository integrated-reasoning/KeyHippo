# verify_api_key

Validate an API key and return its associated context.

## Synopsis

```sql
keyhippo.verify_api_key(
    key text
) RETURNS jsonb
```

## Description

`verify_api_key` validates an API key in the format `prefix_string.key_string` by:
1. Splitting on the '.' delimiter
2. Looking up the prefix in api_key_metadata
3. Computing SHA-256 hash of the full key
4. Comparing against stored hash
5. Checking expiration and revocation status

## Parameters

| Name | Type | Description |
|------|------|-------------|
| key | text | API key in format `prefix_string.key_string` |

## Return Value

Returns a JSONB object containing:
```json
{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "key_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "scope": "analytics",
    "tenant_id": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
    "metadata": {
        "created_at": "2024-01-01T00:00:00Z",
        "description": "Analytics API"
    }
}
```

Returns NULL if key is invalid.

## Examples

Verify a key:
```sql
SELECT keyhippo.verify_api_key('KH2ABJM1.NBTGK19FH27DJSM4');
```

Use in RLS policy:
```sql
CREATE POLICY read_analytics ON events
    FOR SELECT
    USING (
        (keyhippo.verify_api_key(current_setting('request.header.x-api-key')))->>'scope' = 'analytics'
    );
```

## Error Cases

Invalid format:
```sql
SELECT keyhippo.verify_api_key('invalid-key');
ERROR:  invalid api key format
DETAIL:  Key must be in format prefix_string.key_string
```

Revoked key:
```sql
SELECT keyhippo.verify_api_key('KH2ABJM1.NBTGK19FH27DJSM4');
ERROR:  api key has been revoked
DETAIL:  Key KH2ABJM1.* was revoked at 2024-01-01 00:00:00+00
```

Expired key:
```sql
SELECT keyhippo.verify_api_key('KH2ABJM1.NBTGK19FH27DJSM4');
ERROR:  api key has expired
DETAIL:  Key KH2ABJM1.* expired at 2024-01-01 00:00:00+00
```

## Implementation Notes

1. Function first checks key format to fail fast on invalid input
2. Uses key prefix for efficient metadata lookup
3. Only performs hash comparison if key format and status are valid
4. Records failed verification attempts in audit log
5. Uses constant-time comparison for hash check

## Performance

Key verification uses these indexes:
```sql
CREATE INDEX idx_api_key_prefix ON api_key_metadata(key_prefix);
CREATE INDEX idx_api_key_status ON api_key_metadata(status);
CREATE INDEX idx_api_key_expires ON api_key_metadata(expires_at);
```

Typical verification takes < 1ms when indexes are properly warm.

## See Also

- [create_api_key()](create_api_key.md) - Key generation
- [revoke_api_key()](revoke_api_key.md) - Key invalidation
- [api_key_metadata](../tables/api_key_metadata.md) - Key storage