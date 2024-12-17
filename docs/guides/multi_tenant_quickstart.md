# Multi-Tenant Quickstart

Scale your application with clean tenant isolation and robust access controls.

## Overview

```mermaid
graph TD
    A[API Client] -->|API Key| B[KeyHippo Auth]
    B -->|Tenant Context| C[RLS Policies]
    C -->|Access Control| D[Resources]
    E[User] -->|JWT| B
    F[Admin] -->|Impersonation| B
```

## Setup

1. Install dependencies:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

2. Install KeyHippo:
```sql
\i sql/keyhippo.sql
```

## Tenant Architecture

1. Create tenant tables:
```sql
CREATE TABLE tenants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    settings jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT now()
);

CREATE TABLE tenant_members (
    tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    role text NOT NULL,
    PRIMARY KEY (tenant_id, user_id)
);
```

2. Enable RLS:
```sql
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members ENABLE ROW LEVEL SECURITY;
```

## Access Control

1. Create tenant access function:
```sql
CREATE OR REPLACE FUNCTION public.has_tenant_access(tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, keyhippo
AS $$
DECLARE
    ctx record;
    key_data jsonb;
BEGIN
    -- Get authentication context
    SELECT * INTO ctx FROM keyhippo.current_user_context();
    
    -- Check direct membership
    IF EXISTS (
        SELECT 1 FROM tenant_members
        WHERE user_id = ctx.user_id
        AND tenant_id = $1
    ) THEN
        RETURN true;
    END IF;
    
    -- Check API key claims
    key_data := keyhippo.key_data();
    RETURN (
        key_data IS NOT NULL AND
        (key_data->'claims'->>'tenant_id')::uuid = $1
    );
END;
$$;
```

2. Apply RLS policies:
```sql
-- Tenant access policy
CREATE POLICY tenant_access_policy ON tenants
    FOR ALL TO authenticated, anon
    USING (has_tenant_access(id));

-- Resource policy template
CREATE POLICY resource_tenant_policy ON resource_table
    FOR ALL TO authenticated, anon
    USING (has_tenant_access(tenant_id));
```

## API Keys

1. Create tenant-specific API key:
```sql
CREATE OR REPLACE FUNCTION create_tenant_api_key(
    tenant_id uuid,
    description text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    key_record record;
BEGIN
    -- Verify tenant access
    IF NOT has_tenant_access(tenant_id) THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Create API key
    SELECT * INTO key_record FROM keyhippo.create_api_key(
        description,
        'tenant'
    );
    
    -- Add tenant claim
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        jsonb_build_object(
            'tenant_id', tenant_id,
            'created_at', now()
        )
    );
    
    RETURN key_record.api_key;
END;
$$;
```

## Security

1. Enable audit logging:
```sql
-- Update configuration
INSERT INTO keyhippo_internal.config (key, value)
VALUES 
    ('enable_audit_logging', 'true'),
    ('audit_retention_days', '90');
```

2. Configure key expiration:
```sql
-- Set default key expiration to 90 days
UPDATE keyhippo_internal.config
SET value = '90'
WHERE key = 'key_expiry_notification_hours';
```

## Testing

1. Set up test data:
```sql
DO $$
DECLARE
    tenant_id uuid;
    test_user_id uuid;
BEGIN
    -- Create test tenant
    INSERT INTO tenants (name)
    VALUES ('Acme Corp')
    RETURNING id INTO tenant_id;
    
    -- Create test user
    SELECT id INTO test_user_id
    FROM auth.users
    WHERE email = 'test@example.com';
    
    -- Add membership
    INSERT INTO tenant_members (tenant_id, user_id, role)
    VALUES (tenant_id, test_user_id, 'admin');
END $$;
```

2. Test the setup:
```sql
-- Create test API key
SELECT create_tenant_api_key(
    'tenant_id_here',
    'Test API Key'
);

-- Test access
SELECT has_tenant_access('tenant_id_here');
```

## Performance Tips

1. **Index Critical Fields**
```sql
CREATE INDEX idx_tenant_members_user_id 
    ON tenant_members(user_id);

CREATE INDEX idx_resources_tenant_id 
    ON resources(tenant_id);
```

2. **Batch Operations**
```sql
-- Example: Bulk user assignment
INSERT INTO tenant_members (tenant_id, user_id, role)
SELECT 
    tenant_id,
    unnest(user_ids) as user_id,
    'member' as role
FROM json_array_elements_text('["user1", "user2"]') as user_ids;
```

## Next Steps

- Implement [Custom Claims](../api/functions/update_key_claims.md)
- Set up [Key Rotation](api_key_patterns.md#key-rotation)
- Configure [Audit Logging](../api/tables/audit_log.md)

## Related Resources

- [API Key Patterns](api_key_patterns.md)
- [Multi-Tenant Guide](multi_tenant.md)
- [Security Best Practices](../api/security/rls_policies.md)