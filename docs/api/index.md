# KeyHippo API Documentation

## Table of Contents

1. [Schemas](#schemas)
2. [Tables](#tables)
3. [Functions](#functions)
4. [Triggers](#triggers)
5. [Custom Types](#custom-types)
6. [Permissions](#permissions)
7. [Security](#security)

## Schemas

KeyHippo uses multiple schemas to organize its functionality:

- [`keyhippo`](schemas/keyhippo.md) - Main schema for API key and scope management
- [`keyhippo_internal`](schemas/keyhippo_internal.md) - Internal configuration and utilities
- [`keyhippo_rbac`](schemas/keyhippo_rbac.md) - Role-Based Access Control functionality
- [`keyhippo_impersonation`](schemas/keyhippo_impersonation.md) - User impersonation capabilities

## Tables

### KeyHippo Schema
- [`api_key_metadata`](tables/api_key_metadata.md) - Stores API key metadata
- [`api_key_secrets`](tables/api_key_secrets.md) - Securely stores API key hashes
- [`scopes`](tables/scopes.md) - Defines available API key scopes
- [`scope_permissions`](tables/scope_permissions.md) - Maps scopes to permissions
- [`audit_log`](tables/audit_log.md) - Audit trail for system actions

### RBAC Schema
- [`groups`](tables/groups.md) - User groups for organization
- [`roles`](tables/roles.md) - Roles within groups
- [`permissions`](tables/permissions.md) - Available permissions
- [`role_permissions`](tables/role_permissions.md) - Maps roles to permissions
- [`user_group_roles`](tables/user_group_roles.md) - User assignments to groups and roles

### Internal Schema
- [`config`](tables/config.md) - System configuration

### Impersonation Schema
- [`impersonation_state`](tables/impersonation_state.md) - Tracks active impersonation sessions

## Functions

### API Key Management
- [`create_api_key()`](functions/create_api_key.md) - Create new API keys
- [`verify_api_key()`](functions/verify_api_key.md) - Validate API keys
- [`revoke_api_key()`](functions/revoke_api_key.md) - Revoke API keys
- [`rotate_api_key()`](functions/rotate_api_key.md) - Rotate existing API keys
- [`update_key_claims()`](functions/update_key_claims.md) - Update API key claims
- [`key_data()`](functions/key_data.md) - Retrieve API key metadata

### Authentication & Authorization
- [`current_user_context()`](functions/current_user_context.md) - Get current user context
- [`authorize()`](functions/authorize.md) - Check permission authorization
- [`is_authorized()`](functions/is_authorized.md) - Check resource authorization

### RBAC Management
- [`create_group()`](functions/create_group.md) - Create user groups
- [`create_role()`](functions/create_role.md) - Create roles
- [`assign_role_to_user()`](functions/assign_role_to_user.md) - Assign roles to users
- [`assign_permission_to_role()`](functions/assign_permission_to_role.md) - Assign permissions to roles

### Impersonation
- [`login_as_user()`](functions/login_as_user.md) - Impersonate a user
- [`login_as_anon()`](functions/login_as_anon.md) - Impersonate anonymous user
- [`logout()`](functions/logout.md) - End impersonation session

### System Functions
- [`initialize_keyhippo()`](functions/initialize_keyhippo.md) - Initialize the system
- [`initialize_existing_project()`](functions/initialize_existing_project.md) - Set up existing project
- [`check_request()`](functions/check_request.md) - PreRequest security check
- [`update_expiring_keys()`](functions/update_expiring_keys.md) - Handle key expiration

## Triggers

- [`keyhippo_audit_rbac_groups`](triggers/audit_triggers.md) - Audit group changes
- [`keyhippo_audit_rbac_roles`](triggers/audit_triggers.md) - Audit role changes
- [`keyhippo_audit_rbac_permissions`](triggers/audit_triggers.md) - Audit permission changes
- [`keyhippo_notify_expiring_key_trigger`](triggers/notify_triggers.md) - Key expiration notifications
- [`keyhippo_assign_default_role_trigger`](triggers/role_triggers.md) - Default role assignment

## Custom Types

- [`app_permission`](types/app_permission.md) - System permission enum
- [`app_role`](types/app_role.md) - System role types

## Permissions

- [Row Level Security Policies](security/rls_policies.md) - Table access policies
- [Grants](security/grants.md) - Role-based privileges
- [Function Security](security/function_security.md) - Function execution permissions