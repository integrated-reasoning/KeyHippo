# rotate_api_key

Creates a new API key while revoking an existing one, maintaining the same configuration.

## Syntax

```sql
keyhippo.rotate_api_key(old_api_key_id uuid)
RETURNS TABLE (
    new_api_key text,
    new_api_key_id uuid
)
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| old_api_key_id | uuid | ID of the API key to rotate |

## Returns

| Column | Type | Description |
|--------|------|-------------|
| new_api_key | text | Complete new API key (only shown once) |
| new_api_key_id | uuid | ID of the new API key |

## Security

- SECURITY DEFINER function
- Only key owner or scope admin can rotate
- Maintains existing permissions and claims
- Atomic operation for security

## Example Usage

### Basic Rotation
```sql
SELECT * FROM keyhippo.rotate_api_key('old_key_id_here');
```

### Scheduled Rotation
```sql
CREATE OR REPLACE PROCEDURE rotate_old_keys()
LANGUAGE plpgsql
AS $$
DECLARE
    key_record RECORD;
BEGIN
    FOR key_record IN 
        SELECT id 
        FROM keyhippo.api_key_metadata 
        WHERE created_at < NOW() - INTERVAL '90 days'
        AND NOT is_revoked
    LOOP
        PERFORM keyhippo.rotate_api_key(key_record.id);
    END LOOP;
END;
$$;
```

### With Overlap Period
```sql
DO $$
DECLARE
    new_key_record RECORD;
BEGIN
    -- Create new key
    SELECT * INTO new_key_record 
    FROM keyhippo.rotate_api_key('old_key_id_here');
    
    -- Allow time for deployment
    PERFORM pg_sleep(300);  -- 5 minutes
    
    -- Revoke old key
    PERFORM keyhippo.revoke_api_key('old_key_id_here');
END $$;
```

## Implementation Notes

1. **Rotation Process**
   - Creates new key with same config
   - Copies claims and settings
   - Revokes old key
   - Returns new key details

2. **Data Preservation**
```sql
-- Preserved attributes:
- scope_id
- claims
- description
- user_id
```

3. **Audit Logging**
```sql
-- Rotation events are logged
- Old key revocation
- New key creation
- Relationship between keys
```

## Error Handling

1. **Invalid Key ID**
```sql
-- Raises exception
SELECT * FROM keyhippo.rotate_api_key('invalid_uuid');
```

2. **Already Revoked**
```sql
-- Raises exception
SELECT * FROM keyhippo.rotate_api_key('revoked_key_id');
```

3. **Unauthorized**
```sql
-- Raises exception
SELECT * FROM keyhippo.rotate_api_key('unauthorized_key_id');
```

## Performance

- Single database transaction
- Minimal table operations
- Efficient key generation
- Atomic updates

## Related Functions

- [create_api_key()](create_api_key.md)
- [revoke_api_key()](revoke_api_key.md)
- [verify_api_key()](verify_api_key.md)

## See Also

- [API Key Metadata](../tables/api_key_metadata.md)
- [API Key Secrets](../tables/api_key_secrets.md)
- [Security Best Practices](../security/rls_policies.md)