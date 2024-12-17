# Function Security

Security implementation for KeyHippo functions.

## Function Execution Context

Functions run in one of three contexts:

```sql
-- System context (superuser)
SECURITY DEFINER
SET search_path = keyhippo, public;

-- User context (caller's privileges)
SECURITY INVOKER
SET search_path = keyhippo, public;

-- Restricted context (minimal privileges)
SECURITY DEFINER
SET search_path = keyhippo
SET role keyhippo_restricted;
```

## Function Classifications

System Functions:
```sql
-- Full system access
CREATE FUNCTION initialize_keyhippo()
RETURNS void
SECURITY DEFINER
SET search_path = keyhippo, public
AS $$
    -- System initialization
$$;

-- Database structure changes
CREATE FUNCTION update_schema_version()
RETURNS void
SECURITY DEFINER
SET search_path = keyhippo, public
AS $$
    -- Schema updates
$$;
```

Authentication Functions:
```sql
-- Key verification
CREATE FUNCTION verify_api_key(key text)
RETURNS jsonb
SECURITY DEFINER
SET search_path = keyhippo
AS $$
    -- Hash comparison in secure context
$$;

-- Context management
CREATE FUNCTION current_user_context()
RETURNS jsonb
SECURITY INVOKER
STABLE
AS $$
    -- Read session variables
$$;
```

Data Access Functions:
```sql
-- Resource creation
CREATE FUNCTION create_resource(data jsonb)
RETURNS uuid
SECURITY INVOKER
AS $$
    -- Uses caller's privileges
$$;

-- Secure data fetch
CREATE FUNCTION get_sensitive_data(id uuid)
RETURNS jsonb
SECURITY DEFINER
SET search_path = keyhippo
SET role keyhippo_restricted
AS $$
    -- Minimal privilege access
$$;
```

## Implementation Patterns

Privilege Separation:
```sql
-- Split sensitive operations
CREATE FUNCTION create_api_key(description text)
RETURNS text
SECURITY INVOKER
AS $$
BEGIN
    -- 1. Create metadata (user context)
    PERFORM create_key_metadata($1);
    
    -- 2. Generate key (system context)
    RETURN generate_key_secure();
END;
$$;

-- Secure key generation
CREATE FUNCTION generate_key_secure()
RETURNS text
SECURITY DEFINER
SET search_path = keyhippo
AS $$
BEGIN
    -- Generate and hash key
END;
$$;
```

Session Variable Management:
```sql
-- Set context safely
CREATE FUNCTION set_user_context(ctx jsonb)
RETURNS void
SECURITY DEFINER
SET search_path = keyhippo
AS $$
BEGIN
    -- Validate context
    PERFORM validate_context(ctx);
    
    -- Set session variables
    PERFORM set_config(
        'keyhippo.current_context',
        ctx::text,
        false
    );
END;
$$;

-- Read context safely
CREATE FUNCTION get_session_var(name text)
RETURNS text
SECURITY INVOKER
STABLE
AS $$
BEGIN
    RETURN current_setting(
        'keyhippo.' || name,
        true
    );
END;
$$;
```

Error Handling:
```sql
-- Secure error messages
CREATE FUNCTION handle_auth_error()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
    -- Log detailed error
    PERFORM log_auth_failure(
        SQLSTATE,
        SQLERRM,
        pg_context_info()
    );
    
    -- Return generic message
    RAISE EXCEPTION 'authentication failed'
        USING HINT = 'Check credentials and try again';
END;
$$;
```

## Security Boundaries

Database Roles:
```sql
-- System role
CREATE ROLE keyhippo_system
NOINHERIT;

-- API role
CREATE ROLE keyhippo_api
NOINHERIT;

-- Restricted role
CREATE ROLE keyhippo_restricted
NOINHERIT;

-- Function grants
GRANT EXECUTE ON FUNCTION verify_api_key(text)
TO keyhippo_api;

GRANT EXECUTE ON FUNCTION create_api_key(text)
TO keyhippo_api;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA keyhippo
FROM PUBLIC;
```

Schema Access:
```sql
-- System schema
GRANT USAGE ON SCHEMA keyhippo 
TO keyhippo_system;

-- API schema
GRANT USAGE ON SCHEMA keyhippo 
TO keyhippo_api;

-- Public schema
GRANT USAGE ON SCHEMA keyhippo_public 
TO PUBLIC;
```

Object Access:
```sql
-- Table access
GRANT SELECT, INSERT ON keyhippo.api_key_metadata
TO keyhippo_api;

-- Function access
GRANT EXECUTE ON FUNCTION current_user_context()
TO PUBLIC;
```

## Security Checks

Function Invocation:
```sql
-- Permission check
IF NOT has_permission('create_api_key') THEN
    RAISE EXCEPTION 'permission denied'
        USING HINT = 'Requires create_api_key permission';
END IF;

-- Context validation
IF current_user_context() IS NULL THEN
    RAISE EXCEPTION 'no active context'
        USING HINT = 'Authentication required';
END IF;

-- Resource ownership
IF NOT check_resource_owner(resource_id) THEN
    RAISE EXCEPTION 'access denied'
        USING HINT = 'Resource belongs to different owner';
END IF;
```

Input Validation:
```sql
-- Parameter validation
IF NOT validate_key_format(key_input) THEN
    RAISE EXCEPTION 'invalid key format'
        USING HINT = 'Must match pattern prefix.key';
END IF;

-- JSON schema validation
IF NOT validate_json_schema(
    input_data,
    get_schema('resource_input')
) THEN
    RAISE EXCEPTION 'invalid input format'
        USING HINT = 'Check documentation for schema';
END IF;
```

Rate Limiting:
```sql
-- Rate check
IF NOT check_rate_limit(
    operation := 'create_key',
    window := interval '1 minute',
    max_ops := 10
) THEN
    RAISE EXCEPTION 'rate limit exceeded'
        USING HINT = 'Try again later';
END IF;
```

## Audit Trail

Function Execution:
```sql
-- Audit logging
CREATE FUNCTION audit_function_call()
RETURNS event_trigger
AS $$
BEGIN
    INSERT INTO audit_log (
        event_type,
        event_data
    ) VALUES (
        'function_call',
        jsonb_build_object(
            'function', TG_ARGV[0],
            'args', args_to_json(),
            'user_id', current_user_id(),
            'context', current_user_context()
        )
    );
END;
$$;
```

## See Also

- [RLS Policies](rls_policies.md)
- [Database Grants](grants.md)
- [Audit Configuration](../config.md#audit-configuration)