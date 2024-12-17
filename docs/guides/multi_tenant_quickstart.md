# Multi-Tenant Quickstart

## Installation

Install required extensions:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
```

Initialize KeyHippo:
```sql
SELECT initialize_keyhippo(
    'multi_tenant',
    '{
        "tenant_isolation": true,
        "shared_schemas": false,
        "audit_level": "write"
    }'
);
```

## Create First Tenant

Create tenant record:
```sql
INSERT INTO tenants (
    tenant_id,
    name,
    settings
) VALUES (
    gen_random_uuid(),
    'acme_corp',
    '{
        "max_users": 100,
        "max_storage_gb": 50,
        "features": ["api_access", "audit_log"]
    }'
) RETURNING tenant_id;
```

Initialize tenant schema:
```sql
SELECT setup_tenant_schema('acme_corp');
-- Creates:
-- - Tenant-specific schema
-- - Default roles
-- - Initial admin user
```

## Configure Access

Create tenant admin:
```sql
SELECT create_tenant_admin(
    tenant_id := '550e8400-e29b-41d4-a716-446655440000',
    email := 'admin@acme.com',
    initial_password := 'temp-password'
);
```

Create API key:
```sql
SELECT create_tenant_api_key(
    tenant_id := '550e8400-e29b-41d4-a716-446655440000',
    description := 'Initial Access Key'
);
-- Returns: KH2ABJM1.NBTGK19FH27DJSM4
```

## Add Resources

Create resource table:
```sql
CREATE TABLE resources (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id uuid NOT NULL REFERENCES tenants(tenant_id),
    name text NOT NULL,
    data jsonb,
    created_at timestamptz DEFAULT now(),
    created_by uuid NOT NULL,
    CONSTRAINT valid_name CHECK (length(name) BETWEEN 1 AND 255)
);

-- Enable RLS
ALTER TABLE resources ENABLE ROW LEVEL SECURITY;

-- Create tenant policy
CREATE POLICY tenant_resources ON resources
    FOR ALL
    USING (tenant_id = current_tenant_id());
```

Add sample data:
```sql
WITH tenant AS (
    SELECT tenant_id, name 
    FROM tenants 
    WHERE name = 'acme_corp'
    LIMIT 1
)
INSERT INTO resources (
    tenant_id,
    name,
    data,
    created_by
) VALUES (
    (SELECT tenant_id FROM tenant),
    'Sample Resource',
    '{"type": "document", "status": "draft"}',
    current_user_id()
);
```

## Test Access

Connect as tenant:
```sql
-- Set context
SELECT set_tenant_context('550e8400-e29b-41d4-a716-446655440000');

-- Try access
SELECT count(*) FROM resources;
```

Test API key:
```sql
-- Verify key
SELECT verify_api_key('KH2ABJM1.NBTGK19FH27DJSM4');

-- Check access
SELECT * FROM resources 
WHERE tenant_id = current_tenant_id()
LIMIT 5;
```

## Add Users

Create tenant user:
```sql
SELECT create_tenant_user(
    tenant_id := '550e8400-e29b-41d4-a716-446655440000',
    email := 'user@acme.com',
    role := 'editor'
);
```

Assign permissions:
```sql
-- Create role
SELECT create_tenant_role(
    tenant_id := '550e8400-e29b-41d4-a716-446655440000',
    name := 'editor',
    permissions := ARRAY['read_resources', 'edit_resources']
);

-- Assign to user
SELECT assign_tenant_role(
    user_id := '67e55044-10b1-426f-9247-bb680e5fe0c8',
    role := 'editor'
);
```

## Monitor Usage

Check tenant metrics:
```sql
-- Resource usage
SELECT 
    t.name as tenant,
    count(r.*) as resource_count,
    max(r.created_at) as last_created
FROM tenants t
LEFT JOIN resources r ON r.tenant_id = t.tenant_id
GROUP BY t.tenant_id, t.name;

-- API usage
SELECT 
    date_trunc('hour', created_at) as hour,
    count(*) as requests,
    count(DISTINCT user_id) as unique_users
FROM request_log
WHERE tenant_id = '550e8400-e29b-41d4-a716-446655440000'
AND created_at > now() - interval '24 hours'
GROUP BY 1
ORDER BY 1;
```

## Common Operations

Switch tenants:
```sql
-- Clear context
SELECT reset_tenant_context();

-- Set new context
SELECT set_tenant_context('91c35b46-8c55-4264-8373-cf4b1ce957b9');
```

Share resources:
```sql
-- Create share
SELECT share_resource(
    resource_id := '550e8400-e29b-41d4-a716-446655440000',
    target_tenant := '91c35b46-8c55-4264-8373-cf4b1ce957b9'
);

-- Access shared
SELECT * FROM resources 
WHERE id IN (
    SELECT resource_id 
    FROM shared_resources 
    WHERE shared_with = current_tenant_id()
);
```

Manage quotas:
```sql
-- Update limits
UPDATE tenants 
SET settings = jsonb_set(
    settings,
    '{max_storage_gb}',
    '100'
)
WHERE tenant_id = '550e8400-e29b-41d4-a716-446655440000';

-- Check usage
SELECT 
    t.name,
    (t.settings->>'max_storage_gb')::int as quota_gb,
    sum(length(r.data::text))/1024.0/1024.0 as used_mb
FROM tenants t
LEFT JOIN resources r ON r.tenant_id = t.tenant_id
GROUP BY t.tenant_id, t.name, t.settings
HAVING sum(length(r.data::text))/1024.0/1024.0 > 
    (t.settings->>'max_storage_gb')::int * 1024;
```

## Troubleshooting

Check tenant status:
```sql
-- Verify tenant
SELECT 
    tenant_id,
    name,
    status,
    settings,
    created_at
FROM tenants
WHERE tenant_id = '550e8400-e29b-41d4-a716-446655440000';

-- Check context
SELECT 
    current_tenant_id() as tenant,
    current_user_id() as user,
    current_setting('app.tenant_name') as name;
```

Review audit log:
```sql
SELECT 
    created_at,
    event_type,
    event_data
FROM audit_log
WHERE tenant_id = '550e8400-e29b-41d4-a716-446655440000'
AND created_at > now() - interval '1 hour'
ORDER BY created_at DESC;
```

## See Also

- [Multi-Tenant Guide](multi_tenant.md)
- [RLS Policies](../api/security/rls_policies.md)
- [Tenant API](../api/tenants.md)