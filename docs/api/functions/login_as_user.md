# login_as_user

Change the current database session's user context.

## Synopsis

```sql
keyhippo.login_as_user(
    user_id uuid,
    reason text DEFAULT NULL
) RETURNS jsonb
```

## Description

`login_as_user` changes the session's user context by:
1. Validating caller's impersonation permission
2. Loading user's roles and permissions
3. Setting session variables
4. Recording impersonation in audit log

## Parameters

| Name | Type | Description |
|------|------|-------------|
| user_id | uuid | Target user ID |
| reason | text | Audit log reason |

## Return Value

Returns user context JSONB:
```json
{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "tenant_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "roles": ["analyst", "reader"],
    "type": "impersonation",
    "metadata": {
        "impersonated_by": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
        "reason": "Debug user permissions",
        "started_at": "2024-01-01T00:00:00Z"
    }
}
```

## Examples

Basic impersonation:
```sql
SELECT login_as_user(
    '550e8400-e29b-41d4-a716-446655440000'::uuid,
    'Debug permission issue'
);
```

Using returned context:
```sql
DO $$
DECLARE
    ctx jsonb;
BEGIN
    SELECT login_as_user('550e8400-e29b-41d4-a716-446655440000') 
    INTO ctx;
    
    RAISE NOTICE 'Logged in as user with roles: %',
        ctx->'roles';
END;
$$;
```

Temporary scope:
```sql
DO $$
BEGIN
    -- Switch context
    PERFORM login_as_user('550e8400-e29b-41d4-a716-446655440000');
    
    -- Do work as user
    PERFORM some_operation();
    
    -- Restore original context
    PERFORM logout();
END;
$$;
```

## Implementation

Session variable setup:
```sql
-- Store full context
SET LOCAL keyhippo.current_context = context_json;

-- Set individual fields for RLS
SET LOCAL keyhippo.current_user_id = user_id;
SET LOCAL keyhippo.current_tenant_id = tenant_id;
SET LOCAL keyhippo.current_roles = roles;
```

## Error Cases

User not found:
```sql
SELECT login_as_user('550e8400-e29b-41d4-a716-446655440000');
ERROR:  user not found
DETAIL:  No user exists with ID 550e8400-e29b-41d4-a716-446655440000
```

Permission denied:
```sql
SELECT login_as_user('550e8400-e29b-41d4-a716-446655440000');
ERROR:  permission denied
DETAIL:  Current user cannot impersonate other users
HINT:   Requires 'impersonate' permission
```

Invalid target:
```sql
SELECT login_as_user('550e8400-e29b-41d4-a716-446655440000');
ERROR:  invalid impersonation target
DETAIL:  Cannot impersonate system users
```

Already impersonating:
```sql
SELECT login_as_user('550e8400-e29b-41d4-a716-446655440000');
ERROR:  nested impersonation not allowed
DETAIL:  Must call logout() before impersonating another user
```

## Permissions Required

Caller must have either:
- 'impersonate' permission
- System administrator access

Some users cannot be impersonated:
- System users
- Higher privilege users
- Users in different tenants

## Audit Trail

Creates audit entries:
```sql
-- Start impersonation
INSERT INTO audit_log (event_type, event_data) VALUES (
    'impersonation_start',
    '{
        "impersonator": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
        "target_user": "550e8400-e29b-41d4-a716-446655440000",
        "reason": "Debug permission issue",
        "roles": ["analyst", "reader"]
    }'
);

-- End impersonation (via logout)
INSERT INTO audit_log (event_type, event_data) VALUES (
    'impersonation_end',
    '{
        "impersonator": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
        "target_user": "550e8400-e29b-41d4-a716-446655440000",
        "duration": "PT1H5M"
    }'
);
```

## See Also

- [logout()](logout.md) - End impersonation
- [login_as_anon()](login_as_anon.md) - Anonymous context
- [current_user_context()](current_user_context.md) - Get context