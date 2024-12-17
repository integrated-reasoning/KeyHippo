# KeyHippo Quickstart

## Installation

Install extensions:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
```

Install KeyHippo:
```sql
CREATE EXTENSION keyhippo;
SELECT initialize_keyhippo();
```

## Create First Key

Generate admin key:
```sql
SELECT create_api_key(
    description := 'Admin API Key',
    scope := 'admin'
);
-- Returns: KH2ABJM1.NBTGK19FH27DJSM4
```

Test key:
```sql
SELECT verify_api_key('KH2ABJM1.NBTGK19FH27DJSM4');
-- Returns:
-- {
--   "key_id": "550e8400-e29b-41d4-a716-446655440000",
--   "scope": "admin",
--   "user_id": "67e55044-10b1-426f-9247-bb680e5fe0c8"
-- }
```

## Protect Resources

Create table:
```sql
CREATE TABLE items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    data jsonb,
    owner_id uuid NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE items ENABLE ROW LEVEL SECURITY;

-- Create policy
CREATE POLICY item_access ON items
    FOR ALL
    USING (
        owner_id = (current_user_context()->>'user_id')::uuid
        OR has_permission('admin')
    );
```

Add data:
```sql
INSERT INTO items (
    name,
    data,
    owner_id
) VALUES (
    'Test Item',
    '{"status": "active"}',
    current_user_id()
);
```

## Manage Access

Create role:
```sql
SELECT create_role(
    name := 'editor',
    description := 'Can edit items'
);

-- Add permissions
SELECT assign_permission_to_role(
    permission := 'edit_items',
    role := 'editor'
);
```

Create user:
```sql
SELECT create_user(
    email := 'editor@example.com',
    initial_password := 'temp-pass'
);

-- Assign role
SELECT assign_role_to_user(
    user_id := '91c35b46-8c55-4264-8373-cf4b1ce957b9',
    role := 'editor'
);
```

Create scoped key:
```sql
SELECT create_api_key(
    description := 'Editor API Key',
    scope := 'editor'
);
```

## Use API Keys

HTTP request:
```bash
# Get items
curl -X GET 'https://api.example.com/items' \
  -H 'x-api-key: KH2ABJM1.NBTGK19FH27DJSM4'

# Create item
curl -X POST 'https://api.example.com/items' \
  -H 'x-api-key: KH2ABJM1.NBTGK19FH27DJSM4' \
  -H 'content-type: application/json' \
  -d '{"name": "New Item", "data": {"status": "draft"}}'
```

Database function:
```sql
-- Check request
SELECT check_request('{
    "method": "POST",
    "path": "/items",
    "headers": {
        "x-api-key": "KH2ABJM1.NBTGK19FH27DJSM4"
    },
    "body": {
        "name": "New Item",
        "data": {"status": "draft"}
    }
}'::jsonb);

-- Create item if authorized
DO $$
DECLARE
    key_data jsonb;
BEGIN
    -- Verify key
    SELECT verify_api_key(
        current_setting('request.header.x-api-key')
    ) INTO key_data;
    
    -- Create item
    IF key_data IS NOT NULL THEN
        INSERT INTO items (
            name,
            data,
            owner_id
        ) VALUES (
            current_setting('request.body.name'),
            current_setting('request.body.data')::jsonb,
            (key_data->>'user_id')::uuid
        );
    END IF;
END;
$$;
```

## Monitor Usage

Check key usage:
```sql
SELECT 
    k.key_prefix,
    k.description,
    count(r.*) as requests,
    max(r.created_at) as last_used
FROM api_key_metadata k
LEFT JOIN request_log r ON r.key_id = k.key_id
WHERE k.status = 'active'
GROUP BY k.key_id, k.key_prefix, k.description
ORDER BY requests DESC;
```

Review audit log:
```sql
SELECT 
    created_at,
    event_type,
    event_data->>'key_prefix' as key,
    event_data->>'path' as path
FROM audit_log
WHERE event_type = 'api_request'
AND created_at > now() - interval '1 hour'
ORDER BY created_at DESC;
```

## Key Maintenance

Rotate key:
```sql
SELECT rotate_api_key(
    key_id := '550e8400-e29b-41d4-a716-446655440000',
    grace_period := interval '24 hours'
);
```

Revoke key:
```sql
SELECT revoke_api_key(
    key_id := '550e8400-e29b-41d4-a716-446655440000',
    reason := 'Security audit'
);
```

## Common Tasks

Check permissions:
```sql
-- Direct check
SELECT authorize('edit_items');

-- In RLS policy
CREATE POLICY edit_access ON items
    FOR UPDATE
    USING (authorize('edit_items'));
```

Switch context:
```sql
-- Impersonate user
SELECT login_as_user('91c35b46-8c55-4264-8373-cf4b1ce957b9');

-- Reset context
SELECT logout();
```

## See Also

- [API Key Patterns](api_key_patterns.md)
- [Multi-Tenant Setup](multi_tenant_quickstart.md)
- [Security Guide](../api/security/function_security.md)