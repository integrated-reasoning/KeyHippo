# user_group_roles

Maps users to roles within specific groups.

## Schema

```sql
CREATE TABLE keyhippo_rbac.user_group_roles (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id, role_id)
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| user_id | uuid | User reference |
| group_id | uuid | Group reference |
| role_id | uuid | Role reference |

## Indexes

- Primary Key on `(user_id, group_id, role_id)`
- Index on `user_id`
- Index on `group_id`
- Index on `role_id`

## Security

- RLS enabled
- Requires manage_roles permission
- Audit logged
- Core RBAC table

## Example Usage

### Assign Role
```sql
INSERT INTO keyhippo_rbac.user_group_roles (
    user_id,
    group_id,
    role_id
)
VALUES (
    'user_id_here',
    'group_id_here',
    'role_id_here'
);
```

### Bulk Assignment
```sql
DO $$
DECLARE
    group_id uuid;
    role_id uuid;
BEGIN
    -- Get group and role
    SELECT id INTO group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'Engineering';
    
    SELECT id INTO role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'Engineer'
    AND group_id = group_id;
    
    -- Assign role to team
    INSERT INTO keyhippo_rbac.user_group_roles (
        user_id,
        group_id,
        role_id
    )
    SELECT 
        id,
        group_id,
        role_id
    FROM auth.users
    WHERE email LIKE '%@engineering.com'
    ON CONFLICT DO NOTHING;
END $$;
```

### Query User Roles
```sql
SELECT 
    u.email,
    g.name as group_name,
    r.name as role_name,
    array_agg(p.name) as permissions
FROM keyhippo_rbac.user_group_roles ugr
JOIN auth.users u ON ugr.user_id = u.id
JOIN keyhippo_rbac.groups g ON ugr.group_id = g.id
JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
LEFT JOIN keyhippo_rbac.role_permissions rp ON r.id = rp.role_id
LEFT JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
GROUP BY u.email, g.name, r.name;
```

## Implementation Notes

1. **Access Control**
```sql
-- RLS policy
CREATE POLICY user_group_roles_access_policy ON keyhippo_rbac.user_group_roles
    FOR ALL
    TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));
```

2. **Cascading Deletes**
```sql
-- When user is deleted:
ON DELETE CASCADE

-- When group is deleted:
ON DELETE CASCADE

-- When role is deleted:
ON DELETE CASCADE
```

3. **Composite Key**
```sql
-- Ensures unique assignments
PRIMARY KEY (user_id, group_id, role_id)
```

## Common Patterns

1. **Team Setup**
```sql
DO $$
DECLARE
    group_id uuid;
    admin_role_id uuid;
    user_role_id uuid;
BEGIN
    -- Create group
    INSERT INTO keyhippo_rbac.groups (name)
    VALUES ('New Team')
    RETURNING id INTO group_id;
    
    -- Create roles
    INSERT INTO keyhippo_rbac.roles (name, group_id, role_type)
    VALUES ('Team Lead', group_id, 'admin')
    RETURNING id INTO admin_role_id;
    
    INSERT INTO keyhippo_rbac.roles (name, group_id, role_type)
    VALUES ('Team Member', group_id, 'user')
    RETURNING id INTO user_role_id;
    
    -- Assign lead
    INSERT INTO keyhippo_rbac.user_group_roles
    VALUES ('lead_user_id', group_id, admin_role_id);
    
    -- Assign members
    INSERT INTO keyhippo_rbac.user_group_roles
    SELECT id, group_id, user_role_id
    FROM auth.users
    WHERE team = 'new_team';
END $$;
```

2. **Role Transfer**
```sql
WITH old_roles AS (
    DELETE FROM keyhippo_rbac.user_group_roles
    WHERE user_id = 'old_user_id'
    RETURNING group_id, role_id
)
INSERT INTO keyhippo_rbac.user_group_roles (
    user_id,
    group_id,
    role_id
)
SELECT 
    'new_user_id',
    group_id,
    role_id
FROM old_roles;
```

## Performance Considerations

1. **Efficient Lookups**
```sql
-- Use EXISTS for performance
SELECT EXISTS (
    SELECT 1
    FROM keyhippo_rbac.user_group_roles
    WHERE user_id = 'user_id_here'
    AND group_id = 'group_id_here'
);
```

2. **Batch Operations**
```sql
-- Bulk revoke
DELETE FROM keyhippo_rbac.user_group_roles
WHERE group_id = 'group_id_here'
AND user_id = ANY(ARRAY['user1', 'user2']::uuid[]);
```

## Related Tables

- [groups](groups.md)
- [roles](roles.md)
- [role_permissions](role_permissions.md)

## See Also

- [assign_role_to_user()](../functions/assign_role_to_user.md)
- [authorize()](../functions/authorize.md)
- [RBAC Security](../security/rls_policies.md)