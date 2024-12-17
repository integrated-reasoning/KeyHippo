# assign_role_to_user

Assigns a role to a user within a specific group.

## Syntax

```sql
keyhippo_rbac.assign_role_to_user(
    p_user_id uuid,
    p_group_id uuid,
    p_role_id uuid
)
RETURNS void
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_user_id | uuid | User to assign the role to |
| p_group_id | uuid | Group context for the role |
| p_role_id | uuid | Role to assign |

## Security

- SECURITY INVOKER function
- Requires manage_roles permission
- Audit logged
- Transaction safe

## Performance

- P99 latency: 0.016ms
- Operations/sec: 62,500 (single core)
- Efficient for bulk operations
- Minimal constraints

## Example Usage

### Basic Assignment
```sql
SELECT keyhippo_rbac.assign_role_to_user(
    'user_id_here',
    'group_id_here',
    'role_id_here'
);
```

### Bulk Assignment
```sql
CREATE OR REPLACE FUNCTION assign_team_role(
    team_ids uuid[],
    role_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO keyhippo_rbac.user_group_roles (
        user_id,
        group_id,
        role_id
    )
    SELECT 
        id,
        'group_id_here',
        role_id
    FROM unnest(team_ids) id
    ON CONFLICT (user_id, group_id, role_id) DO NOTHING;
END;
$$;
```

### Complete User Setup
```sql
DO $$
DECLARE
    v_group_id uuid;
    v_role_id uuid;
    v_user_id uuid;
BEGIN
    -- Create group if needed
    SELECT keyhippo_rbac.create_group(
        'New Team',
        'Team description'
    ) INTO v_group_id;
    
    -- Create role if needed
    SELECT keyhippo_rbac.create_role(
        'Team Member',
        'Basic team access',
        v_group_id,
        'user'
    ) INTO v_role_id;
    
    -- Get user ID
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = 'user@example.com';
    
    -- Assign role
    PERFORM keyhippo_rbac.assign_role_to_user(
        v_user_id,
        v_group_id,
        v_role_id
    );
END $$;
```

## Implementation Notes

1. **Role Assignment**
```sql
INSERT INTO keyhippo_rbac.user_group_roles (
    user_id,
    group_id,
    role_id
)
VALUES (
    p_user_id,
    p_group_id,
    p_role_id
)
ON CONFLICT (user_id, group_id, role_id) DO NOTHING;
```

2. **Constraints**
```sql
-- Primary key
PRIMARY KEY (user_id, group_id, role_id)

-- Foreign keys
REFERENCES auth.users(id)
REFERENCES keyhippo_rbac.groups(id)
REFERENCES keyhippo_rbac.roles(id)
```

3. **Audit Logging**
```sql
-- Via trigger
keyhippo_audit_rbac_user_group_roles
```

## Error Handling

1. **Invalid User**
```sql
-- Raises exception
SELECT keyhippo_rbac.assign_role_to_user(
    'invalid_user_id',
    'group_id',
    'role_id'
);
```

2. **Invalid Group**
```sql
-- Raises exception
SELECT keyhippo_rbac.assign_role_to_user(
    'user_id',
    'invalid_group_id',
    'role_id'
);
```

3. **Invalid Role**
```sql
-- Raises exception
SELECT keyhippo_rbac.assign_role_to_user(
    'user_id',
    'group_id',
    'invalid_role_id'
);
```

## Related Functions

- [create_group()](create_group.md)
- [create_role()](create_role.md)
- [assign_permission_to_role()](assign_permission_to_role.md)

## See Also

- [User Group Roles](../tables/user_group_roles.md)
- [Groups](../tables/groups.md)
- [Roles](../tables/roles.md)