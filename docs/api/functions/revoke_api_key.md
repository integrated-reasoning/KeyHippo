# revoke_api_key

Invalidate an API key.

## Synopsis

```sql
keyhippo.revoke_api_key(
    key_id uuid,
    reason text DEFAULT NULL
) RETURNS void
```

## Description

`revoke_api_key` immediately invalidates an API key by:
1. Setting status to 'revoked' in api_key_metadata
2. Recording revocation reason and timestamp
3. Logging revocation in audit_log
4. Invalidating any cached verifications

## Parameters

| Name | Type | Description |
|------|------|-------------|
| key_id | uuid | ID of key to revoke |
| reason | text | Optional reason for audit log |

## Examples

Revoke with reason:
```sql
SELECT revoke_api_key(
    '550e8400-e29b-41d4-a716-446655440000'::uuid,
    'Security incident #1234'
);
```

Revoke by key prefix:
```sql
SELECT revoke_api_key(key_id, 'Rotating old keys')
FROM api_key_metadata
WHERE key_prefix = 'KH2ABJM1';
```

Revoke all keys for user:
```sql
SELECT revoke_api_key(key_id, 'User offboarding')
FROM api_key_metadata
WHERE user_id = '67e55044-10b1-426f-9247-bb680e5fe0c8'
AND status = 'active';
```

## Error Cases

Key not found:
```sql
SELECT revoke_api_key('550e8400-e29b-41d4-a716-446655440000');
ERROR:  key not found
DETAIL:  No active key exists with ID 550e8400-e29b-41d4-a716-446655440000
```

Already revoked:
```sql
SELECT revoke_api_key('550e8400-e29b-41d4-a716-446655440000');
ERROR:  key already revoked
DETAIL:  Key was revoked at 2024-01-01 00:00:00+00
```

Permission denied:
```sql
SELECT revoke_api_key('550e8400-e29b-41d4-a716-446655440000');
ERROR:  permission denied for key
DETAIL:  Current user cannot revoke keys owned by other users
```

## Implementation Notes

Function executes:
```sql
UPDATE api_key_metadata
SET status = 'revoked',
    metadata = jsonb_set(
        metadata,
        '{revocation}',
        jsonb_build_object(
            'reason', $2,
            'timestamp', now(),
            'revoked_by', (current_user_context()->>'user_id')::uuid
        )
    )
WHERE key_id = $1
AND status = 'active'
RETURNING key_id;
```

Followed by audit log entry:
```sql
INSERT INTO audit_log (
    event_type,
    event_data,
    key_id
) VALUES (
    'key_revoked',
    jsonb_build_object(
        'reason', $2,
        'key_prefix', (SELECT key_prefix FROM api_key_metadata WHERE key_id = $1)
    ),
    $1
);
```

## Permissions Required

User must either:
- Own the key being revoked
- Have the 'revoke_any_key' permission
- Be a system administrator

## See Also

- [rotate_api_key()](rotate_api_key.md) - Replace key
- [verify_api_key()](verify_api_key.md) - Check key status
- [api_key_metadata](../tables/api_key_metadata.md) - Key storage