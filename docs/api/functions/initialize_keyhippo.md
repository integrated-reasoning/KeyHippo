# initialize_keyhippo

Initializes KeyHippo for a new installation.

## Syntax

```sql
keyhippo.initialize_keyhippo()
RETURNS void
```

## Security

- SECURITY DEFINER function
- Creates default groups and roles
- Sets up initial permissions
- Configures audit logging

## Example Usage

### Basic Installation
```sql
SELECT keyhippo.initialize_keyhippo();
```

### Complete Setup
```sql
DO $$
BEGIN
    -- Install required extensions
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS pg_net;
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    
    -- Initialize KeyHippo
    PERFORM keyhippo.initialize_keyhippo();
    
    -- Verify installation
    ASSERT EXISTS (
        SELECT 1 FROM keyhippo_rbac.groups
        WHERE name = 'Admin Group'
    );
    
    ASSERT EXISTS (
        SELECT 1 FROM keyhippo_rbac.roles
        WHERE name = 'Admin'
    );
END $$;
```

## Implementation Notes

1. **Default Groups**
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES
    ('Admin Group', 'Group for administrators'),
    ('User Group', 'Group for regular users');
```

2. **Default Roles**
```sql
INSERT INTO keyhippo_rbac.roles (name, description, group_id, role_type)
VALUES
    ('Admin', 'Administrator role', admin_group_id, 'admin'),
    ('User', 'Regular user role', user_group_id, 'user');
```

3. **Default Permissions**
```sql
INSERT INTO keyhippo_rbac.permissions (name, description)
VALUES
    ('manage_groups', 'Manage groups'),
    ('manage_roles', 'Manage roles'),
    ('manage_permissions', 'Manage permissions'),
    ('manage_scopes', 'Manage scopes'),
    ('manage_api_keys', 'Manage API keys'),
    ('manage_user_attributes', 'Manage user attributes');
```

4. **Configuration**
```sql
INSERT INTO keyhippo_internal.config (key, value, description)
VALUES
    ('enable_key_expiry_notifications', 'true', 'Enable notifications'),
    ('key_expiry_notification_hours', '72', 'Hours before expiry'),
    ('enable_http_logging', 'false', 'HTTP logging flag');
```

## Error Handling

1. **Already Initialized**
```sql
-- Safe to run multiple times
-- Updates existing values
SELECT keyhippo.initialize_keyhippo();
```

2. **Missing Extensions**
```sql
-- Raises exception
-- Install required extensions first
SELECT keyhippo.initialize_keyhippo();
```

## Initialization Steps

1. **Schema Creation**
   - Creates all required schemas
   - Sets up tables and types
   - Enables RLS

2. **Default Data**
   - Creates admin and user groups
   - Sets up basic roles
   - Assigns default permissions

3. **System Configuration**
   - Sets up notifications
   - Configures audit logging
   - Initializes cron jobs

4. **Security Setup**
   - Enables RLS policies
   - Sets up audit triggers
   - Configures permissions

## Verification

```sql
-- Check schemas
SELECT EXISTS (
    SELECT 1 FROM information_schema.schemata
    WHERE schema_name = 'keyhippo'
);

-- Check default groups
SELECT COUNT(*) FROM keyhippo_rbac.groups;

-- Check permissions
SELECT COUNT(*) FROM keyhippo_rbac.permissions;

-- Check configuration
SELECT COUNT(*) FROM keyhippo_internal.config;
```

## Related Functions

- [initialize_existing_project()](initialize_existing_project.md)
- [assign_default_role()](assign_default_role.md)
- [check_request()](check_request.md)

## See Also

- [Configuration](../tables/config.md)
- [Groups](../tables/groups.md)
- [Permissions](../tables/permissions.md)