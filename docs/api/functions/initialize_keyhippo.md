# initialize_keyhippo

Initialize the KeyHippo schema and base configuration.

## Synopsis

```sql
keyhippo.initialize_keyhippo(
    mode text DEFAULT 'standard',
    options jsonb DEFAULT NULL
) RETURNS void
```

## Description

`initialize_keyhippo` creates database objects:
1. Creates schemas (keyhippo, keyhippo_rbac, keyhippo_internal)
2. Creates tables, indexes, and constraints
3. Initializes default roles and permissions
4. Sets up audit logging
5. Creates RLS policies

## Parameters

| Name | Type | Description |
|------|------|-------------|
| mode | text | 'standard' or 'enterprise' |
| options | jsonb | Optional configuration |

## Example Usage

Basic initialization:
```sql
-- Must run as superuser
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
SELECT initialize_keyhippo();
```

Enterprise setup:
```sql
SELECT initialize_keyhippo(
    'enterprise',
    '{
        "audit_level": "full",
        "require_key_rotation": true,
        "max_key_age_days": 90,
        "password_policy": "strong"
    }'
);
```

Custom configuration:
```sql
SELECT initialize_keyhippo(
    'standard',
    '{
        "schemas": {
            "rbac": "custom_rbac",
            "internal": "custom_internal"
        },
        "default_roles": ["reader", "writer", "admin"]
    }'
);
```

## Implementation Details

Schema Creation:
```sql
CREATE SCHEMA IF NOT EXISTS keyhippo;
CREATE SCHEMA IF NOT EXISTS keyhippo_rbac;
CREATE SCHEMA IF NOT EXISTS keyhippo_internal;
```

Core Tables:
```sql
-- API key storage
CREATE TABLE keyhippo.api_key_metadata (
    key_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    key_prefix text NOT NULL,
    ...
);

CREATE TABLE keyhippo.api_key_secrets (
    key_id uuid PRIMARY KEY REFERENCES api_key_metadata,
    key_hash text NOT NULL,
    ...
);

-- Audit logging
CREATE TABLE keyhippo.audit_log (
    event_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    event_type text NOT NULL,
    ...
);
```

Default Roles:
```sql
INSERT INTO keyhippo_rbac.roles (name, description) VALUES
('admin', 'Full system access'),
('user', 'Standard user access'),
('service', 'API service account');
```

Default Permissions:
```sql
INSERT INTO keyhippo_rbac.permissions 
    (name, resource_type, actions) VALUES
('manage_keys', 'api_key', 
    ARRAY['create', 'read', 'update', 'delete']),
('read_keys', 'api_key', 
    ARRAY['read']),
...
```

## Configuration Options

Audit Levels:
```json
{
    "audit_level": {
        "minimal": "errors and security events",
        "standard": "all write operations",
        "full": "all operations"
    }
}
```

Password Policies:
```json
{
    "password_policy": {
        "basic": "8 chars minimum",
        "standard": "12 chars, mixed case, numbers",
        "strong": "16 chars, special chars, entropy check"
    }
}
```

Key Rotation:
```json
{
    "require_key_rotation": true,
    "max_key_age_days": 90,
    "rotation_reminder_days": 14,
    "allow_grace_period": true
}
```

## Error Cases

Schema exists:
```sql
SELECT initialize_keyhippo();
ERROR:  schema already initialized
DETAIL:  KeyHippo is already installed in this database
HINT:   Use initialize_existing_project() to add to existing install
```

Invalid mode:
```sql
SELECT initialize_keyhippo('invalid');
ERROR:  invalid initialization mode
DETAIL:  Mode must be 'standard' or 'enterprise'
```

Permission denied:
```sql
SELECT initialize_keyhippo();
ERROR:  permission denied
DETAIL:  Must be superuser to initialize KeyHippo
```

Invalid options:
```sql
SELECT initialize_keyhippo('standard', '{"invalid": true}');
ERROR:  invalid configuration option
DETAIL:  Unknown option "invalid"
HINT:   See documentation for valid options
```

## Permissions Required

- Must be database superuser
- Must have CREATE SCHEMA privilege
- Must have permission to install extensions

## Post-Installation

After initialization:
1. Create first admin user
```sql
SELECT create_admin_user('admin@example.com');
```

2. Create first API key
```sql
SELECT create_api_key('Initial Admin Key');
```

3. Test installation
```sql
SELECT verify_installation();
```

## See Also

- [initialize_existing_project()](initialize_existing_project.md)
- [verify_installation()](verify_installation.md)
- [Configuration Reference](../config.md)