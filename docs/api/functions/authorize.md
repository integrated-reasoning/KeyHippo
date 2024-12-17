# authorize

Check if current user has a specific permission.

## Synopsis

```sql
keyhippo.authorize(
    permission text,
    resource_id uuid DEFAULT NULL,
    options jsonb DEFAULT NULL
) RETURNS boolean
```

## Description

`authorize` evaluates permission grants by checking:
1. Direct role permissions
2. Inherited role permissions
3. Group-based permissions
4. Permission conditions
5. Resource-specific grants

## Parameters

| Name | Type | Description |
|------|------|-------------|
| permission | text | Permission to check |
| resource_id | uuid | Optional specific resource |
| options | jsonb | Check options |

## Examples

Basic check:
```sql
SELECT authorize('read_data');
```

Resource-specific:
```sql
SELECT authorize(
    'modify_item', 
    '550e8400-e29b-41d4-a716-446655440000'
);
```

With options:
```sql
SELECT authorize(
    'api_access',
    options := '{
        "require_mfa": true,
        "check_ip": true
    }'
);
```

In RLS policy:
```sql
CREATE POLICY item_access ON items
    FOR ALL
    USING (
        authorize('access_item', id)
    );
```

## Implementation

Permission resolution SQL:
```sql
WITH RECURSIVE role_perms AS (
    -- Direct role permissions
    SELECT 
        p.name as permission,
        rp.conditions
    FROM user_group_roles ugr
    JOIN role_permissions rp ON rp.role_id = ugr.role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    WHERE ugr.user_id = current_user_id()
    AND (ugr.expires_at IS NULL OR ugr.expires_at > now())
    
    UNION
    
    -- Inherited permissions
    SELECT 
        p.name,
        rp.conditions
    FROM role_perms rp0
    JOIN role_inheritance ri ON ri.parent_role_id = rp0.role_id
    JOIN role_permissions rp ON rp.role_id = ri.child_role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
)
SELECT EXISTS (
    SELECT 1 FROM role_perms
    WHERE permission = $1
    AND evaluate_conditions(conditions, $2, $3)
);
```

Condition evaluation:
```sql
CREATE FUNCTION evaluate_conditions(
    conditions jsonb,
    resource_id uuid,
    options jsonb
) RETURNS boolean AS $$
DECLARE
    result boolean;
BEGIN
    -- Time window check
    IF conditions ? 'time_window' THEN
        IF NOT check_time_window(
            (conditions->'time_window'->>'start')::time,
            (conditions->'time_window'->>'end')::time,
            (conditions->'time_window'->>'timezone')::text
        ) THEN
            RETURN false;
        END IF;
    END IF;

    -- Resource ownership
    IF conditions ? 'require_ownership' THEN
        IF NOT check_resource_owner(
            resource_id,
            current_user_id()
        ) THEN
            RETURN false;
        END IF;
    END IF;

    -- IP restrictions
    IF conditions ? 'ip_ranges' THEN
        IF NOT check_ip_range(
            current_client_ip(),
            conditions->'ip_ranges'
        ) THEN
            RETURN false;
        END IF;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql STABLE;
```

## Error Cases

Invalid permission:
```sql
SELECT authorize('invalid');
ERROR:  invalid permission
DETAIL:  Permission "invalid" does not exist
```

Invalid resource:
```sql
SELECT authorize('read_item', 'invalid-uuid');
ERROR:  invalid resource id
DETAIL:  Resource with ID invalid-uuid not found
```

Invalid conditions:
```sql
SELECT authorize('api_access', options := '{"invalid": true}');
ERROR:  invalid option
DETAIL:  Option "invalid" not recognized
```

## Condition Types

Time windows:
```json
{
    "time_window": {
        "start": "09:00",
        "end": "17:00",
        "timezone": "UTC",
        "days": ["MON", "TUE", "WED", "THU", "FRI"]
    }
}
```

Resource limits:
```json
{
    "max_resources": 100,
    "resource_type": "api_key",
    "action": "create"
}
```

Network restrictions:
```json
{
    "ip_ranges": [
        "10.0.0.0/8",
        "172.16.0.0/12"
    ],
    "require_vpn": true
}
```

MFA requirements:
```json
{
    "require_mfa": true,
    "mfa_freshness": "1 hour",
    "allowed_methods": ["totp", "webauthn"]
}
```

## Caching

Permission results are cached per transaction:
```sql
-- Cache structure
keyhippo.permission_cache = {
    "permission:resource": {
        "result": true,
        "evaluated_at": "timestamp",
        "conditions_hash": "hash"
    }
}

-- Cache invalidation
AFTER UPDATE ON role_permissions
AFTER UPDATE ON user_group_roles
ON TRANSACTION COMMIT
```

## Performance

Typical execution times:
- Cached result: < 0.1ms
- Direct permission: < 1ms
- Inherited permission: < 5ms
- With condition evaluation: 1-10ms

Use `EXPLAIN ANALYZE` to debug slow checks:
```sql
EXPLAIN ANALYZE
SELECT authorize('complex_permission', complex_resource_id);
```

## See Also

- [permissions table](../tables/permissions.md)
- [role_permissions table](../tables/role_permissions.md)
- [assign_permission_to_role()](assign_permission_to_role.md)