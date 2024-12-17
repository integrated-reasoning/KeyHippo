# create_role

Creates a new role within a specified group.

## Syntax

```sql
keyhippo_rbac.create_role(
    p_name text,
    p_description text,
    p_group_id uuid,
    p_role_type keyhippo.app_role
)
RETURNS uuid
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_name | text | Name of the role |
| p_description | text | Description of the role's purpose |
| p_group_id | uuid | Group ID this role belongs to |
| p_role_type | keyhippo.app_role | Either 'admin' or 'user' |

## Returns

Returns the UUID of the newly created role.

## Security

- SECURITY INVOKER function
- Requires manage_roles permission
- Audit logged
- Transaction safe

## Example Usage

### Basic Role
```sql
SELECT keyhippo_rbac.create_role(
    'Developer',
    'Software developer role',
    'group_id_here',
    'user'
);
```

### Admin Role
```sql
SELECT keyhippo_rbac.create_role(
    'Team Lead',
    'Team leadership role',
    'group_id_here',
    'admin'
);
```

### Complete Setup
```sql
DO $$
DECLARE
    group_id uuid;
    admin_role_id uuid;
    user_role_id uuid;
BEGIN
    -- Create group
    SELECT keyhippo_rbac.create_group(
        'Engineering',
        'Engineering team'
    ) INTO group_id;
    
    -- Create admin role
    SELECT keyhippo_rbac.create_role(
        'Engineering Lead',
        'Team leadership',
        group_id,
        'admin'
    ) INTO admin_role_id;
    
    -- Create user role
    SELECT keyhippo_rbac.create_role(
        'Engineer',
        'Team member',
        group_id,
        'user'
    ) INTO user_role_id;
    
    -- Assign permissions
    PERFORM keyhippo_rbac.assign_permission_to_role(
        admin_role_id,
        'manage_team'
    );
    
    PERFORM keyhippo_rbac.assign_permission_to_role(
        user_role_id,
        'access_resources'
    );
END $$;
```

## Implementation Notes

1. **Role Creation**
```sql
INSERT INTO keyhippo_rbac.roles (
    name,
    description,
    group_id,
    role_type
)
VALUES (
    p_name,
    p_description,
    p_group_id,
    p_role_type
)
RETURNING id
```

2. **Unique Constraints**
```sql
-- Name must be unique within group
UNIQUE (name, group_id)
```

3. **Role Types**
```sql
CREATE TYPE keyhippo.app_role AS ENUM (
    'admin',
    'user'
);
```

## Error Handling

1. **Invalid Group**
```sql
-- Raises exception
SELECT keyhippo_rbac.create_role(
    'Role Name',
    'Description',
    'invalid_group_id',
    'user'
);
```

2. **Duplicate Role**
```sql
-- Raises exception
SELECT keyhippo_rbac.create_role(
    'Existing Role',
    'Description',
    'group_id',
    'user'
);
```

3. **Invalid Role Type**
```sql
-- Raises exception
SELECT keyhippo_rbac.create_role(
    'Role Name',
    'Description',
    'group_id',
    'invalid_type'
);
```

## Performance

- Single insert operation
- Foreign key validation
- Efficient audit logging
- No cascading effects

## Related Functions

- [create_group()](create_group.md)
- [assign_role_to_user()](assign_role_to_user.md)
- [assign_permission_to_role()](assign_permission_to_role.md)

## See Also

- [Roles Table](../tables/roles.md)
- [Groups Table](../tables/groups.md)
- [Role Permissions](../tables/role_permissions.md)