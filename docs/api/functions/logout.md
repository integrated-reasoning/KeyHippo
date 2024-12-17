# logout

Reset the current database session's authentication context.

## Synopsis

```sql
keyhippo.logout() RETURNS void
```

## Description

`logout` clears all authentication context by:
1. Recording context termination in audit log
2. Resetting all session variables
3. Clearing cached permissions

## Examples

Basic logout:
```sql
SELECT logout();
```

Scoped impersonation:
```sql
DO $$
BEGIN
    -- Switch context
    PERFORM login_as_user('550e8400-e29b-41d4-a716-446655440000');
    
    -- Do work
    PERFORM some_operation();
    
    -- Reset context
    PERFORM logout();
END;
$$;
```

Clear anonymous context:
```sql
DO $$
BEGIN
    PERFORM login_as_anon();
    -- Public operations
    PERFORM logout();
END;
$$;
```

## Implementation

Session cleanup:
```sql
-- Record end of session
INSERT INTO audit_log (
    event_type,
    event_data
) VALUES (
    CASE current_context_type()
        WHEN 'impersonation' THEN 'impersonation_end'
        WHEN 'api_key' THEN 'api_session_end'
        WHEN 'anon' THEN 'anon_context_end'
        ELSE 'session_end'
    END,
    build_session_end_data()
);

-- Clear all session state
RESET keyhippo.current_context;
RESET keyhippo.current_user_id;
RESET keyhippo.current_tenant_id;
RESET keyhippo.current_roles;
RESET keyhippo.permission_cache;
```

## Error Cases

No active context:
```sql
SELECT logout();
ERROR:  no active context
DETAIL:  Nothing to logout from
```

Transaction error:
```sql
SELECT logout();
ERROR:  could not reset session
DETAIL:  Transaction rollback required
HINT:   RESET cannot run inside transaction block
```

## Session Variables

Cleared on logout:
```sql
keyhippo.current_context    -- Full context JSON
keyhippo.current_user_id    -- Active user ID
keyhippo.current_tenant_id  -- Active tenant
keyhippo.current_roles      -- Active roles
keyhippo.permission_cache   -- Permission lookup cache
```

## Audit Trail

Creates audit entry based on context type:

API key session:
```json
{
    "event_type": "api_session_end",
    "event_data": {
        "key_id": "550e8400-e29b-41d4-a716-446655440000",
        "duration": "PT2H",
        "operations": ["SELECT", "INSERT", "UPDATE"]
    }
}
```

Impersonation:
```json
{
    "event_type": "impersonation_end",
    "event_data": {
        "impersonator": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
        "target_user": "550e8400-e29b-41d4-a716-446655440000",
        "duration": "PT5M"
    }
}
```

Anonymous:
```json
{
    "event_type": "anon_context_end",
    "event_data": {
        "client_ip": "10.0.0.1",
        "requests": 45
    }
}
```

## See Also

- [login_as_user()](login_as_user.md) - Start impersonation
- [login_as_anon()](login_as_anon.md) - Anonymous context
- [current_user_context()](current_user_context.md) - Get current context