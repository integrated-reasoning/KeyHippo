# verify_api_key

Verifies an API key and returns user context if valid.

## Syntax

```sql
keyhippo.verify_api_key(api_key text)
RETURNS TABLE (
    user_id uuid,
    scope_id uuid,
    permissions text[]
)
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| api_key | text | The API key to verify, including prefix |

## Returns

Returns a single row with:
- `user_id`: UUID of the key owner
- `scope_id`: UUID of the key's scope (if any)
- `permissions`: Array of permission names granted by the scope

Returns no rows if the key is invalid, revoked, or expired.

## Security

- SECURITY DEFINER function
- Updates `last_used_at` timestamp (rate limited)
- Safe for use in read-only transactions
- No direct table access required

## Performance

- P99 latency: 0.065ms
- Operations/sec: 15,385 (single core)
- Efficient prefix-based lookup
- Cached timestamp updates

## Example Usage

### Basic Verification
```sql
SELECT * FROM keyhippo.verify_api_key('kh_your_api_key_here');
```

### In RLS Policy
```sql
CREATE POLICY "api_access" ON resources
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.verify_api_key(
                current_setting('request.headers', true)::json->>'x-api-key'
            )
        )
    );
```

### With Permission Check
```sql
CREATE POLICY "scoped_access" ON data
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.verify_api_key(
                current_setting('request.headers', true)::json->>'x-api-key'
            ) k
            WHERE 'read_data' = ANY(k.permissions)
        )
    );
```

## Error Handling

1. **Invalid Key Format**
```sql
-- Key too short
SELECT * FROM keyhippo.verify_api_key('invalid');
-- Returns empty result

-- Invalid prefix
SELECT * FROM keyhippo.verify_api_key('invalid_prefix_here');
-- Returns empty result
```

2. **Revoked or Expired Keys**
```sql
-- Both return empty result
SELECT * FROM keyhippo.verify_api_key('kh_revoked_key_here');
SELECT * FROM keyhippo.verify_api_key('kh_expired_key_here');
```

## Implementation Notes

1. **Key Verification Process**
   - Split prefix and key parts
   - Lookup metadata by prefix
   - Verify key hash
   - Check revocation and expiry
   - Return user context

2. **Last Used Tracking**
   ```sql
   -- Updates are rate limited
   UPDATE keyhippo.api_key_metadata
   SET last_used_at = NOW()
   WHERE id = metadata_id
       AND (
           last_used_at IS NULL
           OR last_used_at < NOW() - INTERVAL '1 minute'
       );
   ```

3. **Permission Resolution**
   - Resolves permissions from scope
   - Returns empty array if no scope
   - Permissions are cached in session

## Related Functions

- [create_api_key()](create_api_key.md)
- [revoke_api_key()](revoke_api_key.md)
- [current_user_context()](current_user_context.md)

## See Also

- [API Key Metadata](../tables/api_key_metadata.md)
- [Scopes](../tables/scopes.md)
- [Performance Guide](../../performance.md)