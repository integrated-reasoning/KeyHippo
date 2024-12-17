# Function Security

Security implementation details for KeyHippo functions.

## Security Principles

1. **Least Privilege**
   - Functions use minimum required permissions
   - SECURITY DEFINER only when necessary
   - Explicit search paths

2. **Context Control**
   - User context validation
   - Role-based access
   - Session management

3. **Audit Trail**
   - Function calls logged
   - Changes tracked
   - Error logging

## Function Types

### SECURITY INVOKER

Functions that run with caller's permissions:

```sql
CREATE OR REPLACE FUNCTION keyhippo_rbac.create_group(
    p_name text,
    p_description text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
```

- Used for standard operations
- Relies on RLS policies
- Requires explicit permissions

### SECURITY DEFINER

Functions that run with owner's permissions:

```sql
CREATE OR REPLACE FUNCTION keyhippo.create_api_key(
    key_description text,
    scope_name text DEFAULT NULL
)
RETURNS TABLE (api_key text, api_key_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
```

- Used for privileged operations
- Bypasses RLS
- Requires careful implementation

## Search Path Control

### Fixed Search Path

```sql
CREATE OR REPLACE FUNCTION example()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, keyhippo
AS $$
```

### Temporary Search Path

```sql
CREATE OR REPLACE FUNCTION example()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp
AS $$
```

## Permission Model

### Direct Grants

```sql
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key(text, text)
TO authenticated;
```

### Role-Based Access

```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA keyhippo
TO service_role;
```

## Implementation Patterns

### User Context Validation

```sql
-- Get current user
SELECT user_id INTO authenticated_user_id
FROM keyhippo.current_user_context();

-- Check authorization
IF NOT keyhippo.authorize('required_permission') THEN
    RAISE EXCEPTION 'Unauthorized';
END IF;
```

### Error Handling

```sql
-- Secure error messages
RAISE EXCEPTION 'Invalid input'
    USING HINT = 'Check parameters',
          ERRCODE = 'invalid_parameter_value';
```

### Audit Logging

```sql
-- Log function call
INSERT INTO keyhippo.audit_log (
    action,
    function_name,
    data
)
VALUES (
    'function_call',
    'function_name',
    jsonb_build_object(
        'params', params,
        'user_id', user_id
    )
);
```

## Security Best Practices

1. **Input Validation**
```sql
-- Validate text input
IF LENGTH(input_text) > 255 OR input_text !~ '^[a-zA-Z0-9_ \-]*$' THEN
    RAISE EXCEPTION '[KeyHippo] Invalid input';
END IF;
```

2. **Transaction Control**
```sql
-- Ensure atomic operations
BEGIN;
    -- Perform operations
    -- Raise exception on error
COMMIT;
```

3. **Context Management**
```sql
-- Save and restore context
DECLARE
    original_role text;
BEGIN
    SELECT current_role INTO original_role;
    -- Perform operations
    EXECUTE FORMAT('SET ROLE %I', original_role);
END;
```

## Common Vulnerabilities

1. **Search Path Injection**
   - Always set explicit search_path
   - Use qualified names
   - Avoid dynamic SQL

2. **Privilege Escalation**
   - Minimal SECURITY DEFINER usage
   - Careful permission grants
   - Proper role separation

3. **Information Disclosure**
   - Generic error messages
   - Audit sensitive operations
   - Control data exposure

## Testing Security

### Permission Tests
```sql
-- Test unauthorized access
DO $$
BEGIN
    SET ROLE unauthorized_user;
    ASSERT NOT EXISTS (
        SELECT keyhippo.create_api_key('test', 'default')
    );
END $$;
```

### Context Tests
```sql
-- Test context isolation
DO $$
BEGIN
    ASSERT (
        SELECT user_id FROM keyhippo.current_user_context()
    ) = auth.uid();
END $$;
```

## Related Documentation

- [RLS Policies](rls_policies.md)
- [Grants](grants.md)
- [API Key Security](../../guides/api_key_patterns.md)