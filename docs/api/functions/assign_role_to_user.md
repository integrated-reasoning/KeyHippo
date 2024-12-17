# assign_role_to_user

Grant a role to a user through group membership.

## Synopsis

```sql
keyhippo.assign_role_to_user(
    user_id uuid,
    role_name text,
    group_name text DEFAULT NULL,
    expires_at timestamptz DEFAULT NULL
) RETURNS void
```

## Description

`assign_role_to_user` grants a role to a user by:
1. Finding or creating a group if group_name provided
2. Adding user to that group
3. Assigning role to user-group pair
4. Setting optional expiration
5. Recording assignment in audit log

## Parameters

| Name | Type | Description |
|------|------|-------------|
| user_id | uuid | Target user's ID |
| role_name | text | Name of role to assign |
| group_name | text | Optional group context |
| expires_at | timestamptz | Optional expiration time |

## Examples

Direct role assignment:
```sql
SELECT assign_role_to_user(
    '550e8400-e29b-41d4-a716-446655440000',
    'analyst'
);
```

Role in group context:
```sql
SELECT assign_role_to_user(
    '550e8400-e29b-41d4-a716-446655440000',
    'analyst',
    'data_team'
);
```

Temporary assignment:
```sql
SELECT assign_role_to_user(
    '550e8400-e29b-41d4-a716-446655440000',
    'admin',
    'emergency_access',
    now() + interval '24 hours'
);
```

## Implementation

Role assignment SQL:
```sql
WITH group_id AS (
    SELECT group_id FROM groups 
    WHERE name = $3
    UNION ALL
    SELECT group_id FROM create_group($3)
    LIMIT 1
),
user_group AS (
    INSERT INTO user_groups (user_id, group_id)
    SELECT $1, group_id FROM group_id
    ON CONFLICT DO NOTHING
)
INSERT INTO user_group_roles (
    user_id,
    group_id,
    role_id,
    expires_at
)
SELECT 
    $1,
    group_id,
    r.role_id,
    $4
FROM group_id
JOIN roles r ON r.name = $2
ON CONFLICT (user_id, group_id, role_id) 
DO UPDATE SET expires_at = $4;
```

## Error Cases

Role not found:
```sql
SELECT assign_role_to_user('550e8400-e29b-41d4-a716-446655440000', 'missing');
ERROR:  role not found
DETAIL:  Role "missing" does not exist
```

Invalid user:
```sql
SELECT assign_role_to_user('invalid-uuid', 'analyst');
ERROR:  user not found
DETAIL:  User with ID invalid-uuid does not exist
```

Invalid expiration:
```sql
SELECT assign_role_to_user(
    '550e8400-e29b-41d4-a716-446655440000',
    'admin',
    NULL,
    '2020-01-01'
);
ERROR:  invalid expiration time
DETAIL:  Expiration must be in the future
```

Role conflict:
```sql
SELECT assign_role_to_user('550e8400-e29b-41d4-a716-446655440000', 'user');
ERROR:  role assignment conflict
DETAIL:  User cannot hold roles "admin" and "user" simultaneously
```

## Permissions Required

Caller must have either:
- 'assign_role' permission
- System administrator access
- Group administrator access (if group specified)

## Audit Trail

Creates audit entry:
```json
{
    "event_type": "role_assigned",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "role_name": "analyst",
    "group_name": "data_team",
    "assigned_by": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "expires_at": "2024-01-02T00:00:00Z",
    "timestamp": "2024-01-01T00:00:00Z"
}
```

## See Also

- [create_role()](create_role.md)
- [create_group()](create_group.md)
- [user_group_roles table](../tables/user_group_roles.md)