# key_data

Retrieves metadata for the current API key context.

## Syntax

```sql
keyhippo.key_data()
RETURNS jsonb
```

## Returns

Returns a JSONB object containing:
- `id`: UUID of the API key
- `description`: Key description
- `claims`: Custom claims object

Returns NULL if no valid API key is present.

## Security

- SECURITY DEFINER function
- Safe for use in RLS policies
- Read-only access to metadata
- No sensitive data exposure

## Example Usage

### Basic Retrieval
```sql
SELECT keyhippo.key_data();
```

### In RLS Policy
```sql
CREATE POLICY "tenant_access" ON tenants
    FOR ALL
    USING (
        id = (keyhippo.key_data()->'claims'->>'tenant_id')::uuid
    );
```

### Claim Checking
```sql
CREATE OR REPLACE FUNCTION check_tenant_access(tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    key_data jsonb;
BEGIN
    key_data := keyhippo.key_data();
    RETURN (
        key_data IS NOT NULL AND
        (key_data->'claims'->>'tenant_id')::uuid = tenant_id
    );
END;
$$;
```

## Implementation Notes

1. **Data Source**
```sql
-- Reads from header
current_setting('request.headers', true)::json->>'x-api-key'
```

2. **Return Format**
```json
{
    "id": "uuid-here",
    "description": "Key description",
    "claims": {
        "tenant_id": "uuid-here",
        "role": "admin",
        "custom_claim": "value"
    }
}
```

3. **Performance**
   - Caches results per transaction
   - Minimal metadata lookup
   - Efficient for RLS use

## Error Handling

1. **No API Key**
```sql
-- Returns NULL
SELECT keyhippo.key_data();
```

2. **Invalid Key**
```sql
-- Returns NULL
SELECT keyhippo.key_data();
```

3. **Claim Access**
```sql
-- Safe navigation
SELECT COALESCE(
    (keyhippo.key_data()->'claims'->>'missing')::text,
    'default'
);
```

## Related Functions

- [current_user_context()](current_user_context.md)
- [verify_api_key()](verify_api_key.md)
- [update_key_claims()](update_key_claims.md)

## See Also

- [API Key Metadata](../tables/api_key_metadata.md)
- [Security Policies](../security/rls_policies.md)