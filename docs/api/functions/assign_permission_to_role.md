# assign_permission_to_role

Grant a permission to a role.

## Synopsis

```sql
keyhippo.assign_permission_to_role(
    permission_name text,
    role_name text,
    conditions jsonb DEFAULT NULL
) RETURNS void
```

## Description

`assign_permission_to_role` creates a permission grant by:
1. Looking up permission and role IDs
2. Creating role-permission mapping
3. Setting optional grant conditions
4. Recording assignment in audit log

## Parameters

| Name | Type | Description |
|------|------|-------------|
| permission_name | text | Name of permission |
| role_name | text | Name of target role |
| conditions | jsonb | Optional grant conditions |

## Examples

Basic grant:
```sql
SELECT assign_permission_to_role(
    'read_data',
    'analyst'
);
```

Conditional grant:
```sql
SELECT assign_permission_to_role(
    'modify_data',
    'analyst',
    '{"time_window": {"start": "09:00", "end": "17:00"}}'
);
```

Resource-specific grant:
```sql
SELECT assign_permission_to_role(
    'manage_keys',
    'key_admin',
    '{"max_keys": 100, "key_types": ["api", "service"]}'
);
```

## Implementation

Permission assignment SQL:
```sql
INSERT INTO keyhippo_rbac.role_permissions (
    role_id,
    permission_id,
    conditions,
    granted_at
)
SELECT 
    r.role_id,
    p.permission_id,
    $3,
    now()
FROM keyhippo_rbac.roles r
JOIN keyhippo_rbac.permissions p ON true
WHERE r.name = $2
AND p.name = $1
ON CONFLICT (role_id, permission_id) 
DO UPDATE SET 
    conditions = $3,
    granted_at = now();
```

## Error Cases

Permission not found:
```sql
SELECT assign_permission_to_role('invalid', 'analyst');
ERROR:  permission not found
DETAIL:  Permission "invalid" does not exist
```

Role not found:
```sql
SELECT assign_permission_to_role('read_data', 'missing');
ERROR:  role not found
DETAIL:  Role "missing" does not exist
```

Invalid conditions:
```sql
SELECT assign_permission_to_role(
    'read_data',
    'analyst',
    '{"time_window": "always"}'
);
ERROR:  invalid conditions format
DETAIL:  time_window must contain start and end times
```

Permission conflict:
```sql
SELECT assign_permission_to_role('write_data', 'readonly');
ERROR:  permission conflict
DETAIL:  Role "readonly" cannot have write permissions
```

## Grant Conditions

Supported condition types:

Time windows:
```json
{
    "time_window": {
        "start": "09:00",
        "end": "17:00",
        "timezone": "UTC"
    }
}
```

Resource limits:
```json
{
    "max_resources": 100,
    "resource_types": ["api_key", "role"],
    "scope": "tenant"
}
```

IP restrictions:
```json
{
    "ip_ranges": [
        "10.0.0.0/8",
        "172.16.0.0/12"
    ]
}
```

## Permissions Required

Caller must have either:
- 'assign_permission' grant
- System administrator access

## Audit Trail

Creates audit entry:
```json
{
    "event_type": "permission_assigned",
    "permission": "read_data",
    "role": "analyst",
    "conditions": {
        "time_window": {
            "start": "09:00",
            "end": "17:00"
        }
    },
    "granted_by": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "timestamp": "2024-01-01T00:00:00Z"
}
```

## See Also

- [create_role()](create_role.md)
- [role_permissions table](../tables/role_permissions.md)
- [permissions table](../tables/permissions.md)