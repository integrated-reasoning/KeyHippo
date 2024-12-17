# initialize_existing_project

Initializes KeyHippo for an existing Supabase project, handling existing users.

## Syntax

```sql
keyhippo.initialize_existing_project()
RETURNS void
```

## Security

- SECURITY DEFINER function
- Assigns roles to existing users
- Maintains existing permissions
- Safe for running on active projects

## Example Usage

### Basic Migration
```sql
SELECT keyhippo.initialize_existing_project();
```

### Complete Migration
```sql
DO $$
BEGIN
    -- Backup existing roles
    CREATE TEMP TABLE user_roles_backup AS
    SELECT * FROM auth.users;
    
    -- Initialize KeyHippo
    PERFORM keyhippo.initialize_existing_project();
    
    -- Verify migration
    ASSERT EXISTS (
        SELECT 1 
        FROM keyhippo_rbac.user_group_roles ugr
        JOIN auth.users u ON u.id = ugr.user_id
    );
END $$;
```

## Implementation Notes

1. **User Migration**
```sql
-- Assign default role to all users
INSERT INTO keyhippo_rbac.user_group_roles (
    user_id,
    group_id,
    role_id
)
SELECT 
    u.id,
    g.id,
    r.id
FROM auth.users u
CROSS JOIN (
    SELECT id FROM keyhippo_rbac.groups 
    WHERE name = 'User Group'
) g
CROSS JOIN (
    SELECT id FROM keyhippo_rbac.roles 
    WHERE name = 'User'
) r
ON CONFLICT DO NOTHING;
```

2. **System Setup**
```sql
-- Initialize base system
PERFORM keyhippo.initialize_keyhippo();

-- Set up default scope
INSERT INTO keyhippo.scopes (name, description)
VALUES ('default', 'Default scope for API keys')
ON CONFLICT DO NOTHING;
```

## Migration Steps

1. **System Initialization**
   - Creates schemas and tables
   - Sets up default groups and roles
   - Configures security policies

2. **User Migration**
   - Maps existing users to roles
   - Preserves existing data
   - Sets up default permissions

3. **Verification**
   - Checks user migration
   - Validates permissions
   - Ensures system integrity

## Error Handling

1. **Already Initialized**
```sql
-- Safe to run multiple times
-- Updates missing data only
SELECT keyhippo.initialize_existing_project();
```

2. **Data Conflicts**
```sql
-- Handles duplicates gracefully
-- Uses ON CONFLICT clauses
SELECT keyhippo.initialize_existing_project();
```

## Verification

```sql
-- Check user migration
SELECT 
    COUNT(DISTINCT user_id) as migrated_users,
    COUNT(DISTINCT role_id) as assigned_roles
FROM keyhippo_rbac.user_group_roles;

-- Verify permissions
SELECT 
    u.email,
    array_agg(p.name) as permissions
FROM auth.users u
JOIN keyhippo_rbac.user_group_roles ugr ON u.id = ugr.user_id
JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
GROUP BY u.email;
```

## Related Functions

- [initialize_keyhippo()](initialize_keyhippo.md)
- [assign_default_role()](assign_default_role.md)
- [check_request()](check_request.md)

## See Also

- [User Group Roles](../tables/user_group_roles.md)
- [Groups](../tables/groups.md)
- [Roles](../tables/roles.md)