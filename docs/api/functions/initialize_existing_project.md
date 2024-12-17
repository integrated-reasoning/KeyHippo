# initialize_existing_project

Add KeyHippo to an existing database project.

## Synopsis

```sql
keyhippo.initialize_existing_project(
    schema_prefix text DEFAULT 'keyhippo',
    options jsonb DEFAULT NULL
) RETURNS void
```

## Description

`initialize_existing_project` adds KeyHippo to an existing database by:
1. Creating schemas with custom prefix
2. Setting up RLS integrations
3. Adapting to existing users and roles
4. Configuring audit logging
5. Preserving existing permissions

## Parameters

| Name | Type | Description |
|------|------|-------------|
| schema_prefix | text | Prefix for KeyHippo schemas |
| options | jsonb | Installation options |

## Examples

Basic installation:
```sql
SELECT initialize_existing_project('myapp_auth');
-- Creates schemas:
-- myapp_auth
-- myapp_auth_rbac
-- myapp_auth_internal
```

With options:
```sql
SELECT initialize_existing_project(
    'custom_auth',
    '{
        "integrate_users": true,
        "user_table": "public.users",
        "user_id_column": "id",
        "audit_existing": false
    }'
);
```

User integration:
```sql
SELECT initialize_existing_project(
    'app_auth',
    '{
        "user_mapping": {
            "table": "public.users",
            "columns": {
                "id": "user_id",
                "tenant": "tenant_id",
                "role": "initial_role"
            }
        }
    }'
);
```

## Implementation

Schema creation:
```sql
EXECUTE format($sql$
    CREATE SCHEMA IF NOT EXISTS %I;
    CREATE SCHEMA IF NOT EXISTS %I_rbac;
    CREATE SCHEMA IF NOT EXISTS %I_internal;
$sql$, schema_prefix, schema_prefix, schema_prefix);
```

User integration:
```sql
-- Map existing users
INSERT INTO keyhippo_users (user_id, tenant_id)
SELECT id::uuid, tenant_id::uuid
FROM public.users
ON CONFLICT DO NOTHING;

-- Set up initial roles
INSERT INTO user_group_roles (user_id, role_id)
SELECT 
    u.id::uuid,
    r.role_id
FROM public.users u
JOIN roles r ON r.name = u.role
ON CONFLICT DO NOTHING;
```

## Configuration Options

User Integration:
```json
{
    "user_mapping": {
        "table": "public.users",
        "columns": {
            "id": "user_id",
            "tenant": "tenant_id",
            "role": "initial_role"
        },
        "types": {
            "user_id": "uuid",
            "tenant_id": "uuid",
            "role": "text"
        }
    }
}
```

RLS Integration:
```json
{
    "rls_integration": {
        "adapt_policies": true,
        "policy_prefix": "auth_",
        "exclude_tables": ["migrations", "seeds"]
    }
}
```

Audit Configuration:
```json
{
    "audit": {
        "existing_tables": false,
        "exclude_tables": ["logs", "metrics"],
        "min_level": "write"
    }
}
```

## Error Cases

Schema conflict:
```sql
SELECT initialize_existing_project('existing_schema');
ERROR:  schema already exists
DETAIL:  Schema "existing_schema" already exists and is not empty
HINT:   Choose a different schema prefix
```

User table error:
```sql
SELECT initialize_existing_project('auth', '{"user_table": "missing"}');
ERROR:  relation "missing" does not exist
DETAIL:  Specified user table not found
```

Permission error:
```sql
SELECT initialize_existing_project('auth');
ERROR:  permission denied for schema public
DETAIL:  Must have CREATE privilege on target schema
```

Invalid options:
```sql
SELECT initialize_existing_project('auth', '{"invalid": true}');
ERROR:  invalid configuration option
DETAIL:  Unknown option "invalid"
```

## Required Privileges

- CREATE SCHEMA privilege
- CREATE privilege on target schemas
- SELECT privilege on user table (if integrating)
- TRIGGER privilege (if auditing existing tables)

## Post-Installation Steps

1. Update existing policies:
```sql
SELECT adapt_rls_policies(
    table_name := 'public.items',
    user_column := 'owner_id'
);
```

2. Create initial API key:
```sql
SELECT create_initial_key('Migration Key');
```

3. Test integration:
```sql
SELECT verify_integration();
```

## See Also

- [initialize_keyhippo()](initialize_keyhippo.md)
- [adapt_rls_policies()](adapt_rls_policies.md)
- [Schema Reference](../schemas.md)