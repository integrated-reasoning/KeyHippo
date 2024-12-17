# rotate_api_key

Replace an API key while maintaining its metadata and permissions.

## Synopsis

```sql
keyhippo.rotate_api_key(
    key_id uuid,
    grace_period interval DEFAULT '24 hours'
) RETURNS TABLE (
    new_api_key text,
    new_key_id uuid,
    old_key_expires_at timestamptz
)
```

## Description

`rotate_api_key` creates a new API key that inherits the settings of an existing key. The old key remains valid for a grace period to allow clients to migrate. After the grace period, the old key is automatically revoked.

## Parameters

| Name | Type | Description |
|------|------|-------------|
| key_id | uuid | ID of key to rotate |
| grace_period | interval | Time before old key expires |

## Return Value

Returns a table with:
```sql
   new_api_key     | Format: prefix.key
   new_key_id      | UUID of new key
   old_key_expires | Timestamp when old key expires
```

## Examples

Basic rotation:
```sql
SELECT * FROM rotate_api_key('550e8400-e29b-41d4-a716-446655440000');
```

Rotation with custom grace period:
```sql
SELECT * FROM rotate_api_key(
    '550e8400-e29b-41d4-a716-446655440000',
    '72 hours'
);
```

Mass rotation of old keys:
```sql
SELECT key_id, r.new_api_key
FROM api_key_metadata a
LEFT JOIN LATERAL rotate_api_key(a.key_id) r ON true
WHERE a.created_at < now() - interval '90 days'
AND a.status = 'active';
```

## Implementation

1. Begins transaction
2. Creates new key with create_api_key()
3. Copies metadata from old key:
```sql
UPDATE api_key_metadata
SET scope = old.scope,
    tenant_id = old.tenant_id,
    metadata = jsonb_set(
        old.metadata,
        '{rotation}',
        jsonb_build_object(
            'rotated_from', old.key_id,
            'rotated_at', now()
        )
    )
FROM api_key_metadata old
WHERE api_key_metadata.key_id = new_key_id
AND old.key_id = rotating_key_id;
```
4. Sets expiration on old key:
```sql
UPDATE api_key_metadata
SET expires_at = now() + grace_period,
    metadata = jsonb_set(
        metadata,
        '{rotation}',
        jsonb_build_object(
            'rotated_to', new_key_id,
            'rotated_at', now()
        )
    )
WHERE key_id = rotating_key_id;
```
5. Commits transaction

## Error Cases

Key not found:
```sql
ERROR:  key not found
DETAIL:  No active key exists with ID 550e8400-e29b-41d4-a716-446655440000
```

Already rotated:
```sql
ERROR:  key already rotated
DETAIL:  Key was rotated at 2024-01-01 00:00:00+00
HINT:   New key ID: 67e55044-10b1-426f-9247-bb680e5fe0c8
```

Invalid grace period:
```sql
ERROR:  invalid grace period
DETAIL:  Grace period must be between 1 hour and 30 days
```

## Audit Trail

Rotation creates these audit entries:
```sql
event_type | key_created  | For new key
event_type | key_rotated  | For old key
```

Each entry includes:
- Old and new key IDs
- Rotation timestamp
- Grace period
- User who performed rotation

## See Also

- [create_api_key()](create_api_key.md) - Key creation
- [revoke_api_key()](revoke_api_key.md) - Key revocation
- [verify_api_key()](verify_api_key.md) - Key validation