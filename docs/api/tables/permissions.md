# permissions

Defines available permissions that can be assigned to roles.

## Schema

```sql
CREATE TABLE keyhippo_rbac.permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name keyhippo.app_permission UNIQUE NOT NULL,
    description text
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| name | keyhippo.app_permission | Permission name (enum) |
| description | text | Optional description |

## Indexes

- Primary Key on `id`
- Unique index on `name`

## Security

- RLS enabled
- Requires manage_permissions permission
- Audit logged
- Core system table

## Example Usage

### Query Permissions
```sql
SELECT name, description
FROM keyhippo_rbac.permissions
ORDER BY name;
```

### Permission Assignment
```sql
DO $$
DECLARE
    role_id uuid;
BEGIN
    -- Get role
    SELECT id INTO role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'Admin Role';
    
    -- Assign permissions
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    SELECT role_id, id
    FROM keyhippo_rbac.permissions
    WHERE name IN (
        'manage_users',
        'manage_roles',
        'manage_permissions'
    );
END $$;
```

### Check User Permissions
```sql
SELECT 
    u.email,
    array_agg(DISTINCT p.name) as permissions
FROM auth.users u
JOIN keyhippo_rbac.user_group_roles ugr ON u.id = ugr.user_id
JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
WHERE u.id = 'user_id_here'
GROUP BY u.email;
```

## Implementation Notes

1. **Permission Types**
```sql
CREATE TYPE keyhippo.app_permission AS ENUM (
    'manage_groups',
    'manage_roles',
    'manage_permissions',
    'manage_scopes',
    'manage_api_keys',
    'manage_user_attributes'
);
```

2. **Access Control**
```sql
-- RLS policy
CREATE POLICY permissions_access_policy ON keyhippo_rbac.permissions
    FOR ALL
    TO authenticated
    USING (keyhippo.authorize('manage_permissions'))
    WITH CHECK (keyhippo.authorize('manage_permissions'));
```

3. **Default Permissions**
```sql
-- Created during initialization
INSERT INTO keyhippo_rbac.permissions (name, description)
VALUES
    ('manage_groups', 'Manage groups'),
    ('manage_roles', 'Manage roles'),
    ('manage_permissions', 'Manage permissions'),
    ('manage_scopes', 'Manage scopes'),
    ('manage_api_keys', 'Manage API keys'),
    ('manage_user_attributes', 'Manage user attributes');
```

## Common Patterns

1. **Admin Permissions**
```sql
INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT 
    'admin_role_id_here',
    id
FROM keyhippo_rbac.permissions;
```

2. **Scoped Permissions**
```sql
INSERT INTO keyhippo.scope_permissions (scope_id, permission_id)
SELECT 
    'scope_id_here',
    id
FROM keyhippo_rbac.permissions
WHERE name IN ('manage_api_keys', 'manage_scopes');
```

## Permission Hierarchy

1. **System Management**
   - manage_groups
   - manage_roles
   - manage_permissions

2. **Resource Management**
   - manage_scopes
   - manage_api_keys

3. **User Management**
   - manage_user_attributes

## Related Tables

- [role_permissions](role_permissions.md)
- [scope_permissions](scope_permissions.md)
- [roles](roles.md)

## See Also

- [assign_permission_to_role()](../functions/assign_permission_to_role.md)
- [authorize()](../functions/authorize.md)
- [RBAC Security](../security/rls_policies.md)