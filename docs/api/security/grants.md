# Database Grants

Privilege management for KeyHippo objects.

## Role Hierarchy

```sql
-- System roles
CREATE ROLE keyhippo_system NOINHERIT;
CREATE ROLE keyhippo_api NOINHERIT;
CREATE ROLE keyhippo_readonly NOINHERIT;

-- Application roles
CREATE ROLE app_authenticator NOINHERIT;
CREATE ROLE app_user;
CREATE ROLE app_admin;

-- Service roles
CREATE ROLE analytics_service NOINHERIT;
CREATE ROLE backup_service NOINHERIT;
```

## Schema Grants

Core Schema:
```sql
-- System access
GRANT USAGE ON SCHEMA keyhippo TO keyhippo_system;
GRANT USAGE ON SCHEMA keyhippo_internal TO keyhippo_system;

-- API access
GRANT USAGE ON SCHEMA keyhippo TO keyhippo_api;
GRANT USAGE ON SCHEMA keyhippo_public TO PUBLIC;

-- Application access
GRANT USAGE ON SCHEMA keyhippo TO app_authenticator;
GRANT USAGE ON SCHEMA keyhippo_public TO app_user;
```

RBAC Schema:
```sql
-- Admin access
GRANT USAGE ON SCHEMA keyhippo_rbac TO keyhippo_system;
GRANT USAGE ON SCHEMA keyhippo_rbac TO app_admin;

-- Read access
GRANT USAGE ON SCHEMA keyhippo_rbac TO keyhippo_readonly;
GRANT USAGE ON SCHEMA keyhippo_rbac TO app_user;
```

## Table Grants

API Keys:
```sql
-- Metadata access
GRANT SELECT, INSERT ON keyhippo.api_key_metadata 
TO keyhippo_api;

GRANT SELECT ON keyhippo.api_key_metadata 
TO keyhippo_readonly;

-- Secret access
GRANT INSERT ON keyhippo.api_key_secrets 
TO keyhippo_system;

GRANT SELECT ON keyhippo.api_key_secrets 
TO keyhippo_api;
```

RBAC Tables:
```sql
-- Role management
GRANT SELECT, INSERT, UPDATE ON keyhippo_rbac.roles 
TO app_admin;

GRANT SELECT ON keyhippo_rbac.roles 
TO app_user;

-- Permission management
GRANT SELECT, INSERT, UPDATE ON keyhippo_rbac.permissions 
TO app_admin;

GRANT SELECT ON keyhippo_rbac.permissions 
TO app_user;
```

Audit Log:
```sql
-- Write access
GRANT INSERT ON keyhippo.audit_log 
TO keyhippo_system;

-- Read access
GRANT SELECT ON keyhippo.audit_log 
TO app_admin;

GRANT SELECT ON keyhippo.audit_log 
TO analytics_service;
```

## Function Grants

Authentication:
```sql
-- Key management
GRANT EXECUTE ON FUNCTION 
    keyhippo.create_api_key(text),
    keyhippo.verify_api_key(text),
    keyhippo.revoke_api_key(uuid)
TO keyhippo_api;

-- Context management
GRANT EXECUTE ON FUNCTION 
    keyhippo.current_user_context(),
    keyhippo.login_as_anon()
TO PUBLIC;

GRANT EXECUTE ON FUNCTION 
    keyhippo.login_as_user(uuid)
TO app_admin;
```

RBAC Functions:
```sql
-- Role management
GRANT EXECUTE ON FUNCTION 
    keyhippo.create_role(text, text),
    keyhippo.assign_role_to_user(uuid, text)
TO app_admin;

-- Group management
GRANT EXECUTE ON FUNCTION 
    keyhippo.create_group(text),
    keyhippo.add_user_to_group(uuid, uuid)
TO app_admin;
```

System Functions:
```sql
-- Initialization
GRANT EXECUTE ON FUNCTION 
    keyhippo.initialize_keyhippo(),
    keyhippo.update_schema_version()
TO keyhippo_system;

-- Maintenance
GRANT EXECUTE ON FUNCTION 
    keyhippo.rotate_expired_keys(),
    keyhippo.cleanup_audit_log()
TO keyhippo_system;
```

## Default Privileges

New Objects:
```sql
-- Future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo
    GRANT SELECT ON TABLES TO keyhippo_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo_rbac
    GRANT SELECT ON TABLES TO app_user;

-- Future functions
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo
    GRANT EXECUTE ON FUNCTIONS TO keyhippo_api;
```

## Service Account Access

Analytics Service:
```sql
-- Schema access
GRANT USAGE ON SCHEMA keyhippo TO analytics_service;
GRANT USAGE ON SCHEMA keyhippo_rbac TO analytics_service;

-- Table access
GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo 
TO analytics_service;

GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo_rbac 
TO analytics_service;

-- Function access
GRANT EXECUTE ON FUNCTION 
    keyhippo.get_usage_statistics(),
    keyhippo.get_audit_events()
TO analytics_service;
```

Backup Service:
```sql
-- Read access
GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo 
TO backup_service;

GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo_rbac 
TO backup_service;

-- Write access
GRANT INSERT ON keyhippo.backup_log 
TO backup_service;
```

## Revocation

Remove Access:
```sql
-- Remove user access
REVOKE app_user FROM user_role;

-- Remove all access
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA keyhippo 
FROM revoked_role;

REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA keyhippo 
FROM revoked_role;

REVOKE USAGE ON SCHEMA keyhippo FROM revoked_role;
```

## See Also

- [Function Security](function_security.md)
- [RLS Policies](rls_policies.md)
- [Role Management](../functions/create_role.md)