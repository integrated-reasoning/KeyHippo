# Multi-Tenant Access Control with KeyHippo

This guide demonstrates how to implement secure multi-tenant access control using KeyHippo's API key and claims system.

## Overview

Multi-tenant applications need to ensure that:
1. Users can only access their authorized tenants
2. API keys can be scoped to specific tenants
3. Access control is consistent across all authentication methods
4. Policies are atomic and efficient

## Implementation Pattern

### 1. Access Control Functions

Create tenant access control functions that handle both user and API key authentication:

```sql
CREATE OR REPLACE FUNCTION public.can_access_tenant(tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, keyhippo
AS $$
DECLARE
    ctx RECORD;
    key_tenant_id uuid;
    key_data jsonb;
    user_access boolean;
BEGIN
    -- Get current user context
    SELECT * INTO ctx FROM keyhippo.current_user_context();
    
    -- Check user-based access if authenticated
    IF ctx.user_id IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1
            FROM tenant_users
            WHERE user_id = ctx.user_id
            AND tenant_id = $1
        ) INTO user_access;
    ELSE
        user_access := FALSE;
    END IF;

    -- Check API key claims
    key_data := keyhippo.key_data();
    IF key_data IS NOT NULL AND key_data->'claims'->>'tenant_id' IS NOT NULL THEN
        key_tenant_id := (key_data->'claims'->>'tenant_id')::uuid;
    END IF;

    -- Grant access if either check passes
    RETURN COALESCE(user_access, FALSE) 
        OR COALESCE(key_tenant_id = tenant_id, FALSE);
END;
$$;
```

### 2. Resource-Specific Access Control

Create specific access control functions for different resource types:

```sql
CREATE OR REPLACE FUNCTION public.can_access_resource(resource_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, keyhippo
AS $$
DECLARE
    ctx RECORD;
    v_tenant_id uuid;
    key_data jsonb;
    key_user_id uuid;
BEGIN
    -- Get resource's tenant
    SELECT tenant_id INTO v_tenant_id
    FROM resources
    WHERE id = resource_id;

    -- Use tenant access control
    RETURN public.can_access_tenant(v_tenant_id);
END;
$$;
```

### 3. Row Level Security Policies

Apply consistent RLS policies across your schema:

```sql
-- Enable RLS
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE resources ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY tenant_access_policy ON tenants
    FOR ALL TO authenticated, anon
    USING (can_access_tenant(id));

CREATE POLICY resource_access_policy ON resources
    FOR ALL TO authenticated, anon
    USING (can_access_resource(id));
```

### 4. API Key Configuration

Create API keys with tenant-specific claims:

```sql
-- Create an API key for a specific tenant
SELECT * FROM keyhippo.create_api_key(
    'Tenant API Key',
    'default'
);

-- Add tenant claim
SELECT keyhippo.update_key_claims(
    'key_id_here',
    jsonb_build_object('tenant_id', 'tenant_uuid_here')
);
```

## Security Considerations

### Transaction Safety

Wrap policy changes in transactions:

```sql
BEGIN;
    -- Drop existing policies
    DROP POLICY IF EXISTS "tenant_access" ON resources;
    
    -- Create new policies
    CREATE POLICY "tenant_access" ON resources
        FOR ALL TO authenticated, anon
        USING (can_access_tenant(tenant_id));
        
    -- Grant necessary permissions
    GRANT SELECT, UPDATE ON resources TO authenticated;
COMMIT;
```

### Function Security

1. Always use SECURITY DEFINER for access control functions
2. Set explicit search paths
3. Use parameter types that can't be coerced

```sql
CREATE OR REPLACE FUNCTION public.can_access_tenant(tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, keyhippo
AS $$
```

### Permissions

Grant minimal required permissions:

```sql
-- Grant function execution
GRANT EXECUTE ON FUNCTION public.can_access_tenant(uuid) TO authenticated, anon;

-- Grant table access
GRANT SELECT ON public.resources TO authenticated;
GRANT UPDATE ON public.resources TO authenticated;
```

## Best Practices

1. **Consistent Access Control**
   - Use the same access control functions across all policies
   - Handle both user and API key authentication
   - Consider implementing tenant hierarchies if needed

2. **Claims Management**
   - Keep claims minimal and specific
   - Use UUIDs for tenant identifiers
   - Consider claim expiration for sensitive access

3. **Performance**
   - Index tenant_id columns
   - Use efficient joins in access control functions
   - Cache frequent tenant access checks

4. **Atomic Updates**
   - Wrap policy changes in transactions
   - Consider impact on existing sessions
   - Test policy changes thoroughly

## Example: Complete Tenant System

Here's a complete example of a tenant system:

```sql
-- Tenant structure
CREATE TABLE tenants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    settings jsonb DEFAULT '{}'
);

CREATE TABLE tenant_users (
    tenant_id uuid REFERENCES tenants(id),
    user_id uuid REFERENCES auth.users(id),
    role text NOT NULL,
    PRIMARY KEY (tenant_id, user_id)
);

-- Access control
CREATE OR REPLACE FUNCTION public.can_access_tenant(tenant_id uuid)
RETURNS boolean AS $$
    -- Implementation as above
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Policies
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_access ON tenants
    FOR ALL TO authenticated, anon
    USING (can_access_tenant(id));

CREATE POLICY tenant_user_access ON tenant_users
    FOR ALL TO authenticated, anon
    USING (can_access_tenant(tenant_id));

-- API key creation with tenant claim
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
    -- Create API key
    SELECT * INTO key_record FROM keyhippo.create_api_key(
        description,
        'default'
    );
    
    -- Add tenant claim
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        jsonb_build_object('tenant_id', tenant_id)
    );
    
    RETURN key_record.api_key;
END;
$$;
```

## Related Documentation

- [API Key Claims](../api/functions/update_key_claims.md)
- [Row Level Security](../api/security/rls_policies.md)
- [Current User Context](../api/functions/current_user_context.md)
- [Key Data Function](../api/functions/key_data.md)