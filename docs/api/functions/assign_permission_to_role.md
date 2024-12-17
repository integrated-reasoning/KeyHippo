# assign_permission_to_role

Assigns a permission to a role.

## Syntax

```sql
keyhippo_rbac.assign_permission_to_role(
    p_role_id uuid,
    p_permission_name keyhippo.app_permission
)
RETURNS void
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_role_id | uuid | Role to assign permission to |
| p_permission_name | keyhippo.app_permission | Permission to assign |

## Security

- SECURITY INVOKER function
- Requires manage_roles permission
- Audit logged
- Transaction safe

## Example Usage

### Basic Assignment
```sql
SELECT keyhippo_rbac.assign_permission_to_role(
    'role_id_here',
    'manage_resources'
);
```

### Multiple Permissions
```sql
DO $$
DECLARE
    role_id uuid;
BEGIN
    -- Get role ID
    SELECT id INTO role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'Admin Role';
    
    -- Assign permissions
    PERFORM keyhippo_rbac.assign_permission_to_role(
        role_id,
        'manage_users'
    );
    
    PERFORM keyhippo_rbac.assign_permission_to_role(
        role_id,
        'manage_resources'
    );
    
    PERFORM keyhippo_rbac.assign_permission_to_role(
        role_id,
        'view_analytics'
    );
END $$;
```

### Role Setup with Permissions
```sql
CREATE OR REPLACE FUNCTION setup_role_with_permissions(
    role_name text,
    group_id uuid,
    permissions keyhippo.app_permission[]
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_id uuid;
BEGIN
    -- Create role
    SELECT keyhippo_rbac.create_role(
        role_name,
        'Role with assigned permissions',
        group_id,
        'user'
    ) INTO v_role_id;
    
    -- Assign permissions
    FOR i IN array_lower(permissions, 1)..array_upper(permissions, 1)
    LOOP
        PERFORM keyhippo_rbac.assign_permission_to_role(
            v_role_id,
            permissions[i]
        );
    END LOOP;
    
    RETURN v_role_id;
END;
$$;
```

## Implementation Notes

1. **Permission Assignment**
```sql
INSERT INTO keyhippo_rbac.role_permissions (
    role_id,
    permission_id
)
SELECT 
    p_role_id,
    id
FROM keyhippo_rbac.permissions
WHERE name = p_permission_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
```

2. **Constraints**
```sql
-- Unique assignment
UNIQUE (role_id, permission_id)

-- Foreign keys
REFERENCES keyhippo_rbac.roles(id)
REFERENCES keyhippo_rbac.permissions(id)
```

3. **Audit Logging**
```sql
-- Via trigger
keyhippo_audit_rbac_role_permissions
```

## Error Handling

1. **Invalid Role**
```sql
-- Raises exception
SELECT keyhippo_rbac.assign_permission_to_role(
    'invalid_role_id',
    'manage_users'
);
```

2. **Invalid Permission**
```sql
-- Raises exception
SELECT keyhippo_rbac.assign_permission_to_role(
    'role_id',
    'invalid_permission'
);
```

3. **Duplicate Assignment**
```sql
-- Silently ignored
SELECT keyhippo_rbac.assign_permission_to_role(
    'role_id',
    'existing_permission'
);
```

## Performance

- Single insert operation
- Efficient permission lookup
- No cascading effects
- Minimal constraints

## Related Functions

- [create_role()](create_role.md)
- [assign_role_to_user()](assign_role_to_user.md)
- [authorize()](authorize.md)

## See Also

- [Role Permissions](../tables/role_permissions.md)
- [Permissions](../tables/permissions.md)
- [Roles](../tables/roles.md)