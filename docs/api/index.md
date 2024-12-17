# KeyHippo API Reference

A PostgreSQL extension for API key management and access control. Implements key generation, validation, and row-level security integration.

## Tables

### Core Schema (`keyhippo`)
- [`api_key_metadata`](tables/api_key_metadata.md) - Key prefix, status, expiry
- [`api_key_secrets`](tables/api_key_secrets.md) - Key hashes
- [`scopes`](tables/scopes.md) - Key permission sets
- [`audit_log`](tables/audit_log.md) - Operation history

### RBAC Schema (`keyhippo_rbac`)
- [`groups`](tables/groups.md) - User groups
- [`roles`](tables/roles.md) - User roles 
- [`permissions`](tables/permissions.md) - Available permissions
- [`role_permissions`](tables/role_permissions.md) - Role-permission map
- [`user_group_roles`](tables/user_group_roles.md) - User-role map

### Internal Schema (`keyhippo_internal`) 
- [`config`](tables/config.md) - System configuration

## Functions

### Key Operations

#### Key Management
- [`create_api_key(description text, scope text)`](functions/create_api_key.md)
- [`verify_api_key(key text)`](functions/verify_api_key.md)
- [`revoke_api_key(key_id uuid)`](functions/revoke_api_key.md)
- [`rotate_api_key(old_key_id uuid)`](functions/rotate_api_key.md)

#### Key Context
- [`current_user_context()`](functions/current_user_context.md)
- [`authorize(permission text)`](functions/authorize.md)
- [`key_data(key_id uuid)`](functions/key_data.md)

### Access Control

#### Role Management
- [`create_group(name text)`](functions/create_group.md)
- [`create_role(name text)`](functions/create_role.md)
- [`assign_role_to_user(user_id uuid, role text)`](functions/assign_role_to_user.md)
- [`assign_permission_to_role(permission text, role text)`](functions/assign_permission_to_role.md)

#### User Context
- [`login_as_user(user_id uuid)`](functions/login_as_user.md)
- [`login_as_anon()`](functions/login_as_anon.md)
- [`logout()`](functions/logout.md)

### Installation

#### Setup Functions
- [`initialize_keyhippo()`](functions/initialize_keyhippo.md)
- [`initialize_existing_project(schema text)`](functions/initialize_existing_project.md)

#### Maintenance
- [`check_request()`](functions/check_request.md)
- [`update_expiring_keys()`](functions/update_expiring_keys.md)

## RLS Integration

1. Enable RLS on tables:
```sql
ALTER TABLE my_table ENABLE ROW LEVEL SECURITY;
```

2. Create policies using current_user_context():
```sql
CREATE POLICY read_own_data ON my_table
    FOR SELECT
    USING (
        owner_id = (current_user_context()->>'user_id')::uuid
    );
```

3. Add tenant isolation:
```sql
CREATE POLICY tenant_isolation ON my_table
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
    );
```

## Common Error Patterns

### Authentication Errors
```sql
ERROR:  invalid api key format
ERROR:  api key expired at 2024-01-01 00:00:00+00
ERROR:  api key has been revoked
```

### Authorization Errors
```sql
ERROR:  permission denied for relation my_table
ERROR:  insufficient privileges for scope analytics
ERROR:  tenant access violation
```

### Validation Errors
```sql
ERROR:  value too long for type character varying(255)
ERROR:  null value in column "scope" violates not-null constraint
ERROR:  duplicate key value violates unique constraint
```

## Query Optimization

1. Key lookup uses prefix index:
```sql
CREATE INDEX idx_api_key_prefix ON api_key_metadata(key_prefix);
```

2. Common joins have indexes:
```sql
CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);
CREATE INDEX idx_user_roles_user ON user_group_roles(user_id);
```

3. RLS policy optimization:
```sql
-- Add indexes for columns used in RLS policies
CREATE INDEX idx_owner_id ON my_table(owner_id);
CREATE INDEX idx_tenant_id ON my_table(tenant_id);
```

## Setup Guides

- [Installation Steps](../guides/quickstart.md)
- [Enterprise Setup](../guides/enterprise_quickstart.md)
- [Multi-tenant Configuration](../guides/multi_tenant.md)
- [Key Management Examples](../guides/api_key_patterns.md)