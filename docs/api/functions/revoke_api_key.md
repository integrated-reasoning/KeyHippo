# revoke_api_key

Revokes an API key, preventing any further use.

## Syntax

```sql
keyhippo.revoke_api_key(api_key_id uuid)
RETURNS boolean
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| api_key_id | uuid | ID of the API key to revoke |

## Returns

Returns `true` if the key was successfully revoked, `false` if the key was already revoked or not found.

## Security

- SECURITY DEFINER function
- Only key owner or users with manage_api_keys permission can revoke
- Automatically removes key hash for security
- Action is logged to audit system

## Example Usage

### Basic Revocation
```sql
SELECT keyhippo.revoke_api_key('key_id_here');
```

### With Error Handling
```sql
DO $$
BEGIN
    IF NOT keyhippo.revoke_api_key('key_id_here') THEN
        RAISE EXCEPTION 'Failed to revoke key';
    END IF;
END $$;
```

### Bulk Revocation
```sql
-- Revoke all expired keys
DO $$
DECLARE
    key_record RECORD;
BEGIN
    FOR key_record IN 
        SELECT id 
        FROM keyhippo.api_key_metadata 
        WHERE expires_at < NOW()
    LOOP
        PERFORM keyhippo.revoke_api_key(key_record.id);
    END LOOP;
END $$;
```

## Implementation Notes

1. **Revocation Process**
   - Marks key as revoked in metadata
   - Deletes key hash from secrets
   - Records action in audit log
   - Immediate effect

2. **Authorization Checks**
   ```sql
   -- Checks performed:
   user_id = c_user_id  -- Key owner
   OR
   scope_id = c_scope_id  -- Scope admin
   ```

3. **Cleanup Actions**
   - Removes key hash
   - Updates last_used_at
   - Logs revocation

## Error Handling

1. **Invalid Key ID**
```sql
-- Returns false
SELECT keyhippo.revoke_api_key('invalid_uuid_here');
```

2. **Already Revoked**
```sql
-- Returns false
SELECT keyhippo.revoke_api_key('already_revoked_key_id');
```

3. **Unauthorized**
```sql
-- Raises exception
SELECT keyhippo.revoke_api_key('someone_elses_key_id');
```

## Related Functions

- [create_api_key()](create_api_key.md)
- [verify_api_key()](verify_api_key.md)
- [rotate_api_key()](rotate_api_key.md)

## See Also

- [API Key Metadata](../tables/api_key_metadata.md)
- [API Key Secrets](../tables/api_key_secrets.md)
- [Audit Log](../tables/audit_log.md)