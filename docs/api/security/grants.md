# Grants

Permission grants and role assignments in KeyHippo.

## Schema Access

### Public Access
```sql
-- Schema usage
GRANT USAGE ON SCHEMA keyhippo TO authenticated, anon;
GRANT USAGE ON SCHEMA keyhippo_rbac TO authenticated, anon;
```

### Internal Access
```sql
-- Internal schema
GRANT USAGE ON SCHEMA keyhippo_internal TO postgres;
GRANT ALL PRIVILEGES ON keyhippo_internal.config TO postgres;
```

## Function Execution

### API Key Functions
```sql
-- Core API key management
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo.verify_api_key(text) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key(uuid) TO authenticated;
```

### RBAC Functions
```sql
-- Role management
GRANT EXECUTE ON FUNCTION keyhippo_rbac.create_group(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.create_role(text, text, uuid, keyhippo.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_permission_to_role(uuid, keyhippo.app_permission) TO authenticated;
```

### System Functions
```sql
-- Core functionality
GRANT EXECUTE ON FUNCTION keyhippo.authorize(keyhippo.app_permission) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION keyhippo.current_user_context() TO authenticated;
GRANT EXECUTE ON FUNCTION keyhippo.key_data() TO authenticated, authenticator, anon;
```

## Table Access

### Public Tables
```sql
-- Grant access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo_rbac TO authenticated;
```

### Protected Tables
```sql
-- Revoke sensitive access
REVOKE ALL ON TABLE keyhippo.api_key_secrets FROM authenticated;
```

### Service Role Access
```sql
-- Full access for service role
GRANT ALL ON ALL TABLES IN SCHEMA keyhippo TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA keyhippo_rbac TO service_role;
```

## Role Assignments

### Base Roles
```sql
-- Minimal permissions
GRANT keyhippo_user TO authenticated;
```

### Administrative Roles
```sql
-- Full permissions
GRANT keyhippo_admin TO service_role;
```

## Permission Hierarchy

1. **Anonymous Access**
   - verify_api_key
   - key_data
   - authorize

2. **Authenticated Access**
   - create_api_key
   - revoke_api_key
   - rotate_api_key
   - manage own resources

3. **Administrative Access**
   - manage_groups
   - manage_roles
   - manage_permissions
   - impersonation

## Implementation Examples

### Custom Role Setup
```sql
-- Create custom role
CREATE ROLE api_manager;

-- Grant permissions
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key(text, text) TO api_manager;
GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key(uuid) TO api_manager;
GRANT SELECT ON keyhippo.api_key_metadata TO api_manager;
```

### Function Grants
```sql
-- Grant with specific signature
GRANT EXECUTE ON FUNCTION function_name(param_type) TO role_name;

-- Grant all functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA schema_name TO role_name;
```

### Table Grants
```sql
-- Specific permissions
GRANT SELECT, INSERT ON table_name TO role_name;

-- Schema-wide grants
GRANT USAGE ON SCHEMA schema_name TO role_name;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA schema_name TO role_name;
```

## Security Considerations

1. **Least Privilege**
   - Grant minimum required permissions
   - Use specific grants over wildcards
   - Regular permission audits

2. **Role Separation**
   - Clear role boundaries
   - Function-specific permissions
   - Protected system tables

3. **Grant Management**
   - Document all grants
   - Review grant chains
   - Remove unused grants

## Related Documentation

- [Function Security](function_security.md)
- [RLS Policies](rls_policies.md)
- [Security Best Practices](../../guides/api_key_patterns.md)