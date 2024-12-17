# Row Level Security Policies

KeyHippo uses Postgres Row Level Security (RLS) to enforce access control at the database level. This document details all RLS policies in the system.

## Overview

RLS policies are enabled on all tables across KeyHippo's schemas. These policies ensure that:
- Users can only access their own data
- Administrators can access data based on their permissions
- API keys can only access allowed resources
- System tables are protected from unauthorized access

## KeyHippo Schema Policies

### api_key_metadata

```sql
CREATE POLICY api_key_metadata_access_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        OR keyhippo.authorize('manage_api_keys')
    );
```

Users can only see and manage their own API keys, while administrators with 'manage_api_keys' permission can see all keys.

### api_key_secrets

```sql
CREATE POLICY api_key_secrets_no_access_policy ON keyhippo.api_key_secrets
    FOR ALL TO authenticated
    USING (FALSE);
```

No direct access allowed to API key secrets - all interactions must be through secure functions.

### scopes

```sql
CREATE POLICY scopes_access_policy ON keyhippo.scopes
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_scopes'))
    WITH CHECK (keyhippo.authorize('manage_scopes'));
```

Only users with 'manage_scopes' permission can manage scopes.

## RBAC Schema Policies

### groups

```sql
CREATE POLICY groups_access_policy ON keyhippo_rbac.groups
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_groups'))
    WITH CHECK (keyhippo.authorize('manage_groups'));
```

Only users with 'manage_groups' permission can manage groups.

### roles

```sql
CREATE POLICY roles_access_policy ON keyhippo_rbac.roles
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));
```

Only users with 'manage_roles' permission can manage roles.

### permissions

```sql
CREATE POLICY permissions_access_policy ON keyhippo_rbac.permissions
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_permissions'))
    WITH CHECK (keyhippo.authorize('manage_permissions'));
```

Only users with 'manage_permissions' permission can manage permissions.

### user_group_roles

```sql
CREATE POLICY user_group_roles_access_policy ON keyhippo_rbac.user_group_roles
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));
```

Only users with 'manage_roles' permission can manage user role assignments.

## Internal Schema Policies

### config

```sql
CREATE POLICY config_access_policy ON keyhippo_internal.config
    USING (CURRENT_USER = 'postgres');
```

Only the postgres superuser can access internal configuration.

## Impersonation Schema Policies

### impersonation_state

```sql
CREATE POLICY impersonation_state_access ON keyhippo_impersonation.impersonation_state
    USING (
        CURRENT_USER = 'postgres'
        OR (
            CURRENT_USER = 'anon' 
            AND impersonated_user_id = '00000000-0000-0000-0000-000000000000'::uuid
        )
        OR impersonated_user_id::text = CURRENT_USER
    );
```

Restricts access to impersonation state based on user roles and impersonation status.

## Best Practices

When implementing custom tables that integrate with KeyHippo:

1. Always enable RLS:
```sql
ALTER TABLE your_table ENABLE ROW LEVEL SECURITY;
```

2. Use KeyHippo's authorization function:
```sql
CREATE POLICY your_policy ON your_table
    FOR ALL TO authenticated
    USING (keyhippo.authorize('your_permission'));
```

3. Consider user context:
```sql
CREATE POLICY your_user_policy ON your_table
    FOR ALL TO authenticated
    USING (
        user_id = (SELECT user_id FROM keyhippo.current_user_context())
    );
```

4. Handle API key scopes:
```sql
CREATE POLICY your_scope_policy ON your_table
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.current_user_context() ctx
            WHERE ctx.scope_id = your_table.scope_id
        )
    );
```

## Security Considerations

- All tables have RLS enabled by default
- Policies are enforced even for superusers
- Function security contexts are carefully managed
- API key access is always verified through secure functions
- Audit logging captures all relevant changes
- Impersonation is strictly controlled

## Related Documentation

- [Function Security](function_security.md)
- [Grants](grants.md)
- [Authorization Function](../functions/authorize.md)
- [Current User Context](../functions/current_user_context.md)