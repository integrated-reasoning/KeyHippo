# Multi-Tenant Implementation Guide

## Tenant Isolation

Database schema:
```sql
-- Tenant definition
CREATE TABLE tenants (
    tenant_id uuid PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    settings jsonb,
    status text NOT NULL DEFAULT 'active'
);

-- Resource ownership
ALTER TABLE resources
ADD COLUMN tenant_id uuid REFERENCES tenants(tenant_id);

-- Add tenant isolation
ALTER TABLE resources
ENABLE ROW LEVEL SECURITY;
```

RLS policies:
```sql
-- Basic isolation
CREATE POLICY tenant_isolation ON resources
    FOR ALL
    USING (
        tenant_id = current_tenant_id()
    );

-- Cross-tenant sharing
CREATE POLICY tenant_sharing ON resources
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        OR id = ANY(
            SELECT resource_id 
            FROM shared_resources 
            WHERE shared_with = current_tenant_id()
        )
    );
```

## Implementation Pattern

Session context:
```sql
-- Set context
CREATE FUNCTION set_tenant_context(tid uuid)
RETURNS void AS $$
BEGIN
    PERFORM set_config(
        'app.current_tenant_id',
        tid::text,
        false
    );
END;
$$ LANGUAGE plpgsql;

-- Get context
CREATE FUNCTION current_tenant_id()
RETURNS uuid AS $$
    SELECT NULLIF(
        current_setting('app.current_tenant_id', true),
        ''
    )::uuid;
$$ LANGUAGE sql STABLE;
```

Connection handling:
```sql
-- Connection setup
CREATE FUNCTION setup_connection()
RETURNS void AS $$
BEGIN
    -- Set search path
    PERFORM set_config(
        'search_path',
        current_tenant_schema() || ',public',
        false
    );
    
    -- Set tenant context
    PERFORM set_tenant_context(
        current_tenant_id()
    );
    
    -- Set RLS context
    SET SESSION AUTHORIZATION DEFAULT;
END;
$$ LANGUAGE plpgsql;
```

## Data Separation

Schema-based:
```sql
CREATE FUNCTION create_tenant_schema(tid uuid)
RETURNS void AS $$
BEGIN
    -- Create schema
    EXECUTE format(
        'CREATE SCHEMA tenant_%s',
        replace(tid::text, '-', '')
    );
    
    -- Create tables
    EXECUTE format(
        'CREATE TABLE tenant_%s.resources (...)',
        replace(tid::text, '-', '')
    );
END;
$$ LANGUAGE plpgsql;
```

RLS-based:
```sql
-- Shared tables with RLS
CREATE POLICY tenant_data ON resources
    FOR ALL
    USING (
        tenant_id = current_tenant_id()
    );

-- Variant with inheritance
CREATE POLICY tenant_hierarchy ON resources
    FOR ALL
    USING (
        tenant_id IN (
            SELECT child_id 
            FROM tenant_hierarchy
            WHERE parent_id = current_tenant_id()
        )
    );
```

## Resource Management

Creation:
```sql
CREATE FUNCTION create_resource(data jsonb)
RETURNS uuid AS $$
DECLARE
    rid uuid;
BEGIN
    INSERT INTO resources (
        tenant_id,
        name,
        data
    ) VALUES (
        current_tenant_id(),
        data->>'name',
        data
    )
    RETURNING id INTO rid;
    
    RETURN rid;
END;
$$ LANGUAGE plpgsql;
```

Sharing:
```sql
CREATE FUNCTION share_resource(
    resource_id uuid,
    target_tenant_id uuid
) RETURNS void AS $$
BEGIN
    -- Verify ownership
    IF NOT exists (
        SELECT 1 FROM resources
        WHERE id = resource_id
        AND tenant_id = current_tenant_id()
    ) THEN
        RAISE EXCEPTION 'not resource owner';
    END IF;

    -- Create share
    INSERT INTO shared_resources (
        resource_id,
        shared_with,
        shared_by,
        shared_at
    ) VALUES (
        resource_id,
        target_tenant_id,
        current_user_id(),
        now()
    );
END;
$$ LANGUAGE plpgsql;
```

## Authentication Integration

API key creation:
```sql
CREATE FUNCTION create_tenant_api_key(
    tenant_id uuid,
    description text
) RETURNS text AS $$
DECLARE
    key_string text;
BEGIN
    -- Create key
    SELECT create_api_key(
        description,
        jsonb_build_object(
            'tenant_id', tenant_id,
            'type', 'tenant_key'
        )
    ) INTO key_string;
    
    RETURN key_string;
END;
$$ LANGUAGE plpgsql;
```

Key validation:
```sql
CREATE FUNCTION validate_tenant_key(key text)
RETURNS jsonb AS $$
DECLARE
    key_data jsonb;
BEGIN
    -- Verify key
    SELECT verify_api_key(key)
    INTO key_data;
    
    -- Check tenant context
    IF key_data->>'tenant_id' != current_tenant_id()::text THEN
        RETURN NULL;
    END IF;
    
    RETURN key_data;
END;
$$ LANGUAGE plpgsql;
```

## Role Separation

Tenant roles:
```sql
-- Create tenant-specific role
CREATE FUNCTION create_tenant_role(
    tenant_id uuid,
    role_name text
) RETURNS uuid AS $$
DECLARE
    rid uuid;
BEGIN
    INSERT INTO roles (
        name,
        tenant_id,
        created_at
    ) VALUES (
        role_name,
        tenant_id,
        now()
    )
    RETURNING role_id INTO rid;
    
    RETURN rid;
END;
$$ LANGUAGE plpgsql;
```

Permission assignment:
```sql
CREATE FUNCTION assign_tenant_permission(
    role_id uuid,
    permission text
) RETURNS void AS $$
BEGIN
    -- Verify tenant context
    IF NOT exists (
        SELECT 1 FROM roles
        WHERE role_id = $1
        AND tenant_id = current_tenant_id()
    ) THEN
        RAISE EXCEPTION 'invalid role';
    END IF;

    -- Assign permission
    INSERT INTO role_permissions (
        role_id,
        permission_id
    )
    SELECT 
        $1,
        permission_id
    FROM permissions
    WHERE name = $2;
END;
$$ LANGUAGE plpgsql;
```

## Usage Tracking

Tenant metrics:
```sql
CREATE MATERIALIZED VIEW tenant_metrics AS
SELECT 
    tenant_id,
    date_trunc('hour', created_at) as hour,
    count(*) as request_count,
    count(DISTINCT user_id) as unique_users,
    count(DISTINCT resource_id) as resources_accessed
FROM request_log
WHERE created_at > now() - interval '30 days'
GROUP BY tenant_id, date_trunc('hour', created_at);

REFRESH MATERIALIZED VIEW CONCURRENTLY tenant_metrics;
```

Resource usage:
```sql
CREATE VIEW tenant_resource_usage AS
SELECT 
    t.tenant_id,
    t.name as tenant_name,
    count(r.*) as total_resources,
    sum(r.size_bytes) as storage_used,
    max(r.updated_at) as last_modified
FROM tenants t
LEFT JOIN resources r ON r.tenant_id = t.tenant_id
GROUP BY t.tenant_id, t.name;
```

## See Also

- [Tenant Quickstart](multi_tenant_quickstart.md)
- [RLS Policies](../api/security/rls_policies.md)
- [Database Grants](../api/security/grants.md)