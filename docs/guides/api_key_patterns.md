# API Key Configuration Patterns

This guide demonstrates common patterns for configuring and using API keys with KeyHippo.

## Access Control Patterns

### 1. Tenant-Specific Keys

Configure API keys to access specific tenants:

```sql
-- Create and configure tenant key
DO $$
DECLARE
    key_record record;
    tenant_id uuid := 'tenant_uuid_here';
BEGIN
    -- Create key
    SELECT * INTO key_record 
    FROM keyhippo.create_api_key('Tenant Access Key');
    
    -- Add tenant claim
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        jsonb_build_object(
            'tenant_id', tenant_id,
            'role', 'tenant_admin'
        )
    );
END $$;
```

### 2. User Impersonation Keys

Create API keys that act on behalf of specific users:

```sql
-- Create user-specific key
DO $$
DECLARE
    key_record record;
    user_id uuid := 'user_uuid_here';
BEGIN
    SELECT * INTO key_record 
    FROM keyhippo.create_api_key('User Service Key');
    
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        jsonb_build_object(
            'user_id', user_id,
            'scope', 'user_access'
        )
    );
END $$;
```

### 3. Resource-Scoped Keys

Limit keys to specific resources or operations:

```sql
-- Create resource-scoped key
DO $$
DECLARE
    key_record record;
BEGIN
    SELECT * INTO key_record 
    FROM keyhippo.create_api_key(
        'Analytics Read Key',
        'analytics:read'
    );
    
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        jsonb_build_object(
            'allowed_resources', array['metrics', 'reports'],
            'access_level', 'read'
        )
    );
END $$;
```

## Authorization Functions

### 1. Multi-Context Authorization

Handle both user and API key access:

```sql
CREATE OR REPLACE FUNCTION can_access_resource(resource_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ctx record;
    key_data jsonb;
    resource_type text;
    allowed_resources text[];
BEGIN
    -- Get contexts
    SELECT * INTO ctx 
    FROM keyhippo.current_user_context();
    
    key_data := keyhippo.key_data();
    
    -- Get resource type
    SELECT type INTO resource_type
    FROM resources
    WHERE id = resource_id;
    
    -- Check API key access
    IF key_data IS NOT NULL THEN
        allowed_resources := (key_data->'claims'->>'allowed_resources')::text[];
        IF resource_type = ANY(allowed_resources) THEN
            RETURN true;
        END IF;
    END IF;
    
    -- Fall back to user access
    RETURN check_user_access(ctx.user_id, resource_id);
END;
$$;
```

### 2. Role-Based Access

Implement role checks using API key claims:

```sql
CREATE OR REPLACE FUNCTION has_role(required_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ctx record;
    key_data jsonb;
    key_role text;
BEGIN
    -- Get current context
    SELECT * INTO ctx 
    FROM keyhippo.current_user_context();
    
    -- Check user roles first
    IF ctx.user_id IS NOT NULL THEN
        IF check_user_role(ctx.user_id, required_role) THEN
            RETURN true;
        END IF;
    END IF;
    
    -- Check API key role
    key_data := keyhippo.key_data();
    IF key_data IS NOT NULL THEN
        key_role := key_data->'claims'->>'role';
        RETURN key_role = required_role;
    END IF;
    
    RETURN false;
END;
$$;
```

## Policy Implementation

### 1. Resource Policies

```sql
-- Enable RLS
ALTER TABLE resources ENABLE ROW LEVEL SECURITY;

-- Create flexible access policy
CREATE POLICY resource_access ON resources
    FOR ALL TO authenticated, anon
    USING (
        can_access_resource(id)
        AND (
            -- Check API key access level
            (
                (keyhippo.key_data()->'claims'->>'access_level') = 'admin'
                OR
                (keyhippo.key_data()->'claims'->>'access_level') = 'read' 
                AND current_setting('request.method') = 'GET'
            )
            OR
            -- Check user permissions
            has_role('admin')
        )
    );
```

### 2. Tenant Policies

```sql
-- Enable RLS
ALTER TABLE tenant_data ENABLE ROW LEVEL SECURITY;

-- Create tenant-aware policy
CREATE POLICY tenant_data_access ON tenant_data
    FOR ALL TO authenticated, anon
    USING (
        tenant_id = (keyhippo.key_data()->'claims'->>'tenant_id')::uuid
        OR
        tenant_id IN (
            SELECT t.id 
            FROM tenants t
            JOIN tenant_users tu ON tu.tenant_id = t.id
            WHERE tu.user_id = auth.uid()
        )
    );
```

## Best Practices

### 1. Key Creation

```sql
-- Helper function for key creation
CREATE OR REPLACE FUNCTION create_scoped_key(
    description text,
    scope text,
    claims jsonb
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    key_record record;
BEGIN
    -- Validate claims
    IF NOT validate_claims(claims) THEN
        RAISE EXCEPTION 'Invalid claims structure';
    END IF;

    -- Create key
    SELECT * INTO key_record 
    FROM keyhippo.create_api_key(description, scope);
    
    -- Add claims
    PERFORM keyhippo.update_key_claims(
        key_record.api_key_id,
        claims
    );
    
    RETURN key_record.api_key;
END;
$$;
```

### 2. Claims Validation

```sql
CREATE OR REPLACE FUNCTION validate_claims(claims jsonb)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check required fields
    IF claims->>'tenant_id' IS NULL AND 
       claims->>'user_id' IS NULL AND
       claims->>'role' IS NULL THEN
        RETURN false;
    END IF;
    
    -- Validate UUIDs
    IF claims->>'tenant_id' IS NOT NULL THEN
        PERFORM claims->>'tenant_id'::uuid;
    END IF;
    
    -- Add more validation as needed
    
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        RETURN false;
END;
$$;
```

### 3. Key Rotation

```sql
CREATE OR REPLACE FUNCTION rotate_tenant_key(
    old_key_id uuid,
    tenant_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_key record;
    old_claims jsonb;
BEGIN
    -- Get existing claims
    SELECT claims INTO old_claims
    FROM keyhippo.api_key_metadata
    WHERE id = old_key_id;
    
    -- Create new key with same claims
    SELECT * INTO new_key 
    FROM keyhippo.rotate_api_key(old_key_id);
    
    -- Update claims on new key
    PERFORM keyhippo.update_key_claims(
        new_key.api_key_id,
        old_claims
    );
    
    RETURN new_key.api_key;
END;
$$;
```

## Related Documentation

- [API Key Management](../api/functions/create_api_key.md)
- [Claims Management](../api/functions/update_key_claims.md)
- [Multi-Tenant Guide](multi_tenant.md)
- [Security Best Practices](../api/security/function_security.md)