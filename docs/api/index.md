# KeyHippo API Reference

Complete reference documentation for KeyHippo's API.

## Core Concepts

KeyHippo is built around these key concepts:

1. **API Keys**: Secure authentication tokens with optional claims
2. **RBAC**: Role-based access control with groups and permissions
3. **RLS Integration**: Native PostgreSQL row-level security
4. **Multi-Tenant**: Built-in support for tenant isolation

## API Components

### Authentication

#### API Key Management
- [`create_api_key()`](functions/create_api_key.md) - Create API keys
- [`verify_api_key()`](functions/verify_api_key.md) - Validate keys
- [`revoke_api_key()`](functions/revoke_api_key.md) - Revoke keys
- [`rotate_api_key()`](functions/rotate_api_key.md) - Rotate keys

#### Context & Authorization
- [`current_user_context()`](functions/current_user_context.md) - Get auth context
- [`authorize()`](functions/authorize.md) - Check permissions
- [`key_data()`](functions/key_data.md) - Get key metadata

### Access Control

#### RBAC Management
- [`create_group()`](functions/create_group.md) - Create groups
- [`create_role()`](functions/create_role.md) - Create roles
- [`assign_role_to_user()`](functions/assign_role_to_user.md) - Role assignment
- [`assign_permission_to_role()`](functions/assign_permission_to_role.md) - Permission assignment

#### Administrative
- [`login_as_user()`](functions/login_as_user.md) - User impersonation
- [`login_as_anon()`](functions/login_as_anon.md) - Anonymous access
- [`logout()`](functions/logout.md) - End impersonation

### System Management

#### Setup
- [`initialize_keyhippo()`](functions/initialize_keyhippo.md) - Initial setup
- [`initialize_existing_project()`](functions/initialize_existing_project.md) - Existing project setup

#### Maintenance
- [`check_request()`](functions/check_request.md) - Request validation
- [`update_expiring_keys()`](functions/update_expiring_keys.md) - Key expiration

## Database Schema

### Core Schema (`keyhippo`)
- [`api_key_metadata`](tables/api_key_metadata.md) - Key metadata
- [`api_key_secrets`](tables/api_key_secrets.md) - Secure hashes
- [`scopes`](tables/scopes.md) - API scopes
- [`audit_log`](tables/audit_log.md) - Audit trail

### RBAC Schema (`keyhippo_rbac`)
- [`groups`](tables/groups.md) - User groups
- [`roles`](tables/roles.md) - User roles
- [`permissions`](tables/permissions.md) - Available permissions
- [`role_permissions`](tables/role_permissions.md) - Role-permission mapping
- [`user_group_roles`](tables/user_group_roles.md) - User-role assignment

### Internal Schema (`keyhippo_internal`)
- [`config`](tables/config.md) - System configuration

## Security

- [RLS Policies](security/rls_policies.md) - Access control policies
- [Function Security](security/function_security.md) - Function permissions
- [Grants](security/grants.md) - Database grants

## Best Practices

- Always use `current_user_context()` in RLS policies
- Never store API keys in plaintext
- Use claims for tenant isolation
- Implement proper key rotation
- Monitor the audit log

## Error Handling

All functions follow these error patterns:

1. **Authentication Errors**
   - Invalid API key
   - Expired key
   - Missing permissions

2. **Authorization Errors**
   - Insufficient privileges
   - Invalid tenant access
   - Role conflicts

3. **Validation Errors**
   - Invalid input format
   - Missing required fields
   - Constraint violations

## Performance Considerations

- Use appropriate indexes
- Cache frequent lookups
- Batch operations when possible
- Monitor query performance

## Related Guides

- [QuickStart Guide](../guides/quickstart.md)
- [Enterprise Setup](../guides/enterprise_quickstart.md)
- [Multi-Tenant Guide](../guides/multi_tenant.md)
- [API Key Patterns](../guides/api_key_patterns.md)