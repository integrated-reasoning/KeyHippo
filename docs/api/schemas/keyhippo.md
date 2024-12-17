# keyhippo Schema

The main schema for KeyHippo's API key and access management functionality.

## Overview

The `keyhippo` schema contains the core tables and functions for managing API keys, scopes, and permissions. It provides the primary interface for API key operations and authentication.

## Components

### Tables

- [api_key_metadata](../tables/api_key_metadata.md) - API key information
- [api_key_secrets](../tables/api_key_secrets.md) - Secure key hashes
- [scopes](../tables/scopes.md) - Available API scopes
- [scope_permissions](../tables/scope_permissions.md) - Scope-permission mappings
- [audit_log](../tables/audit_log.md) - System audit trail

### Functions

#### API Key Management
- [create_api_key()](../functions/create_api_key.md)
- [verify_api_key()](../functions/verify_api_key.md)
- [revoke_api_key()](../functions/revoke_api_key.md)
- [rotate_api_key()](../functions/rotate_api_key.md)
- [update_key_claims()](../functions/update_key_claims.md)
- [key_data()](../functions/key_data.md)

#### Authentication
- [current_user_context()](../functions/current_user_context.md)
- [authorize()](../functions/authorize.md)
- [is_authorized()](../functions/is_authorized.md)

#### System Management
- [initialize_keyhippo()](../functions/initialize_keyhippo.md)
- [initialize_existing_project()](../functions/initialize_existing_project.md)
- [check_request()](../functions/check_request.md)
- [update_expiring_keys()](../functions/update_expiring_keys.md)

### Custom Types

- [app_permission](../types/app_permission.md)
- [app_role](../types/app_role.md)

## Security

- All tables have RLS enabled
- Functions are properly secured with SECURITY DEFINER where needed
- Careful permission management through grants
- API key secrets are never exposed

## Usage

### Initialize KeyHippo

```sql
-- For new projects
SELECT keyhippo.initialize_keyhippo();

-- For existing projects
SELECT keyhippo.initialize_existing_project();
```

### Create and Use API Keys

```sql
-- Create a new key
SELECT * FROM keyhippo.create_api_key('Production API');

-- Use in RLS policies
CREATE POLICY "api_access" ON "public"."resources"
    FOR ALL
    USING (
        user_id = (SELECT user_id FROM keyhippo.current_user_context())
    );
```

### Manage Scopes

```sql
-- Create a scope
INSERT INTO keyhippo.scopes (name, description)
VALUES ('analytics', 'Analytics API access');

-- Create scoped key
SELECT * FROM keyhippo.create_api_key('Analytics API', 'analytics');
```

## Best Practices

1. Always use the provided functions for API key operations
2. Never access api_key_secrets directly
3. Use current_user_context() for authentication checks
4. Implement proper RLS policies
5. Monitor the audit_log for security events

## Integration

### With Supabase

```sql
-- Enable PostgREST pre-request check
ALTER ROLE authenticator 
SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Notify PostgREST
NOTIFY pgrst, 'reload config';
```

### With Custom Tables

```sql
-- Example RLS policy using KeyHippo
CREATE POLICY "custom_access" ON "public"."your_table"
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.current_user_context()
            WHERE 'your_permission' = ANY(permissions)
        )
    );
```

## Related Schemas

- [keyhippo_rbac](keyhippo_rbac.md) - Role-based access control
- [keyhippo_internal](keyhippo_internal.md) - Internal configuration
- [keyhippo_impersonation](keyhippo_impersonation.md) - User impersonation