# roles

Defines roles that can be assigned to users within groups.

## Schema

```sql
CREATE TABLE keyhippo_rbac.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    description text,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups(id) ON DELETE CASCADE,
    role_type keyhippo.app_role NOT NULL DEFAULT 'user',
    UNIQUE (name, group_id)
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| name | text | Role name (unique per group) |
| description | text | Optional description |
| group_id | uuid | Group this role belongs to |
| role_type | keyhippo.app_role | Either 'admin' or 'user' |

## Indexes

- Primary Key on `id`
- Unique index on `(name, group_id)`
- Index on `group_id`

## Security

- RLS enabled
- Requires manage_roles permission
- Audit logged
- Referenced by permissions

## Example Usage

### Create Role
```sql
INSERT INTO keyhippo_rbac.roles (
    name,
    description,
    group_id,
    role_type
)
VALUES (
    'Senior Engineer',
    'Senior engineering position',
    'group_id_here',
    'user'
);
```

### Complete Role Setup
```sql
DO $$
DECLARE
    group_id uuid;
    admin_role_id uuid;
    user_role_id uuid;
BEGIN
    -- Create group
    INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES ('Engineering', 'Engineering team')
    RETURNING id INTO group_id;
    
    -- Create admin role
    INSERT INTO keyhippo_rbac.roles (
        name, description, group_id, role_type
    )
    VALUES (
        'Engineering Lead',
        'Team leadership role',
        group_id,
        'admin'
    )
    RETURNING id INTO admin_role_id;
    
    -- Create user role
    INSERT INTO keyhippo_rbac.roles (
        name, description, group_id, role_type
    )
    VALUES (
        'Engineer',
        'Team member role',
        group_id,
        'user'
    )
    RETURNING id INTO user_role_id;
    
    -- Assign permissions
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    SELECT admin_role_id, id
    FROM keyhippo_rbac.permissions
    WHERE name IN ('manage_team', 'manage_code');
END $$;
```

### Query Role Structure
```sql
SELECT 
    r.name as role_name,
    r.role_type,
    g.name as group_name,
    array_agg(p.name) as permissions
FROM keyhippo_rbac.roles r
JOIN keyhippo_rbac.groups g ON r.group_id = g.id
LEFT JOIN keyhippo_rbac.role_permissions rp ON r.id = rp.role_id
LEFT JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
GROUP BY r.id, r.name, r.role_type, g.name;
```

## Implementation Notes

1. **Access Control**
```sql
-- RLS policy
CREATE POLICY roles_access_policy ON keyhippo_rbac.roles
    FOR ALL
    TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));
```

2. **Role Types**
```sql
CREATE TYPE keyhippo.app_role AS ENUM (
    'admin',
    'user'
);
```

3. **Cascading Deletes**
```sql
-- When group is deleted:
ON DELETE CASCADE
```

## Common Patterns

1. **Engineering Roles**
```sql
INSERT INTO keyhippo_rbac.roles (name, description, group_id, role_type)
VALUES
    ('Engineering Lead', 'Team leadership', group_id, 'admin'),
    ('Senior Engineer', 'Senior position', group_id, 'user'),
    ('Engineer', 'Standard position', group_id, 'user'),
    ('Junior Engineer', 'Entry level', group_id, 'user');
```

2. **Product Roles**
```sql
INSERT INTO keyhippo_rbac.roles (name, description, group_id, role_type)
VALUES
    ('Product Manager', 'Product leadership', group_id, 'admin'),
    ('Product Owner', 'Product ownership', group_id, 'user'),
    ('Product Analyst', 'Analysis role', group_id, 'user');
```

## Related Tables

- [groups](groups.md)
- [role_permissions](role_permissions.md)
- [user_group_roles](user_group_roles.md)

## See Also

- [create_role()](../functions/create_role.md)
- [assign_role_to_user()](../functions/assign_role_to_user.md)
- [RBAC Security](../security/rls_policies.md)