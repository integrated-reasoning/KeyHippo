# scopes

Defines permission sets for API keys.

## Table Definition

```sql
CREATE TABLE keyhippo.scopes (
    scope_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    permissions text[] NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    tenant_id uuid,
    metadata jsonb,
    CONSTRAINT valid_scope_name CHECK (name ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT unique_scope_name UNIQUE NULLS NOT DISTINCT (name, tenant_id),
    CONSTRAINT valid_permissions CHECK (array_length(permissions, 1) > 0)
);
```

## Indexes

```sql
-- Scope lookup
CREATE UNIQUE INDEX idx_scope_name 
ON scopes(name) 
WHERE tenant_id IS NULL;

-- Tenant scope lookup
CREATE UNIQUE INDEX idx_tenant_scope_name 
ON scopes(tenant_id, name) 
WHERE tenant_id IS NOT NULL;

-- Permission search
CREATE INDEX idx_scope_permissions 
ON scopes USING gin(permissions);
```

## Default Scopes

System creates these on initialization:
```sql
INSERT INTO scopes (name, description, permissions) VALUES
(
    'admin',
    'Full system access',
    ARRAY[
        'manage_keys',
        'manage_roles',
        'manage_groups',
        'view_audit_log'
    ]
),
(
    'readonly',
    'Read-only access',
    ARRAY[
        'read_data',
        'export_reports'
    ]
),
(
    'service',
    'Service account access',
    ARRAY[
        'create_resources',
        'read_resources',
        'update_resources'
    ]
);
```

## Example Queries

List available scopes:
```sql
SELECT 
    name,
    description,
    array_length(permissions, 1) as permission_count,
    created_at
FROM scopes
WHERE tenant_id = current_tenant_id()
   OR tenant_id IS NULL
ORDER BY name;
```

Find scopes by permission:
```sql
SELECT 
    name,
    description
FROM scopes
WHERE 'read_data' = ANY(permissions)
AND (tenant_id = current_tenant_id() 
     OR tenant_id IS NULL)
ORDER BY name;
```

Key usage by scope:
```sql
SELECT 
    s.name as scope,
    count(*) as total_keys,
    count(*) FILTER (
        WHERE k.status = 'active'
    ) as active_keys
FROM scopes s
LEFT JOIN api_key_metadata k ON k.scope_id = s.scope_id
GROUP BY s.scope_id, s.name
ORDER BY total_keys DESC;
```

## Implementation

Scope validation:
```sql
CREATE FUNCTION validate_scope_permissions()
RETURNS trigger AS $$
BEGIN
    -- Check permissions exist
    IF EXISTS (
        SELECT 1 
        FROM unnest(NEW.permissions) p(name)
        LEFT JOIN permissions pm ON pm.name = p.name
        WHERE pm.permission_id IS NULL
    ) THEN
        RAISE EXCEPTION 'invalid permission in scope';
    END IF;
    
    -- Check permission conflicts
    IF EXISTS (
        SELECT 1
        FROM permission_conflicts pc
        WHERE pc.permission_a = ANY(NEW.permissions)
        AND pc.permission_b = ANY(NEW.permissions)
    ) THEN
        RAISE EXCEPTION 'conflicting permissions in scope';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## Permission Sets

Read-only access:
```sql
CREATE SCOPE readonly
PERMISSIONS [
    'read_resources',
    'export_data',
    'view_metrics'
];
```

API management:
```sql
CREATE SCOPE api_admin
PERMISSIONS [
    'create_endpoints',
    'modify_endpoints',
    'view_metrics',
    'manage_rate_limits'
];
```

Data access:
```sql
CREATE SCOPE data_access
PERMISSIONS [
    'read_data',
    'write_data',
    'delete_data',
    'export_reports'
];
```

## Triggers

```sql
-- Validate permissions
CREATE TRIGGER validate_scope
    BEFORE INSERT OR UPDATE ON scopes
    FOR EACH ROW
    EXECUTE FUNCTION validate_scope_permissions();

-- Audit changes
CREATE TRIGGER audit_scope_changes
    AFTER INSERT OR UPDATE OR DELETE ON scopes
    FOR EACH ROW
    EXECUTE FUNCTION audit_scope_change();

-- Update dependent keys
CREATE TRIGGER update_key_permissions
    AFTER UPDATE OF permissions ON scopes
    FOR EACH ROW
    EXECUTE FUNCTION update_key_permissions();
```

## RLS Policies

```sql
-- View scopes
CREATE POLICY view_scopes ON scopes
    FOR SELECT
    USING (
        tenant_id IS NULL 
        OR tenant_id = current_tenant_id()
    );

-- Manage scopes
CREATE POLICY manage_scopes ON scopes
    FOR ALL
    USING (
        has_permission('manage_scopes')
        AND (
            tenant_id IS NULL 
            OR tenant_id = current_tenant_id()
        )
    );
```

## See Also

- [permissions](permissions.md)
- [api_key_metadata](api_key_metadata.md)
- [create_api_key()](../functions/create_api_key.md)