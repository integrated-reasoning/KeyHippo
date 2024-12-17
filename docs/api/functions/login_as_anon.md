# login_as_anon

Set the current database session to anonymous context.

## Synopsis

```sql
keyhippo.login_as_anon() RETURNS jsonb
```

## Description

`login_as_anon` sets minimal anonymous access by:
1. Clearing existing session context
2. Setting anonymous role
3. Applying anonymous RLS policies
4. Recording transition in audit log

## Return Value

Returns anonymous context JSONB:
```json
{
    "type": "anon",
    "roles": ["anon"],
    "metadata": {
        "previous_context": "api_key|user|impersonation",
        "started_at": "2024-01-01T00:00:00Z"
    }
}
```

## Examples

Switch to anonymous:
```sql
SELECT login_as_anon();
```

Anonymous operation block:
```sql
DO $$
BEGIN
    -- Switch to anonymous
    PERFORM login_as_anon();
    
    -- Public data access
    PERFORM public_operation();
    
    -- Restore original context
    PERFORM logout();
END;
$$;
```

Check anonymous access:
```sql
SELECT EXISTS (
    SELECT 1 FROM items
    WHERE public = true
    AND keyhippo.login_as_anon() IS NOT NULL
) as has_public_access;
```

## Implementation

Session variable setup:
```sql
-- Clear existing context
RESET keyhippo.current_context;
RESET keyhippo.current_user_id;
RESET keyhippo.current_tenant_id;
RESET keyhippo.current_roles;

-- Set anonymous context
SET LOCAL keyhippo.current_context = '{"type": "anon", "roles": ["anon"]}';
SET LOCAL keyhippo.current_roles = '{anon}';
```

## Error Cases

Already anonymous:
```sql
SELECT login_as_anon();
ERROR:  already in anonymous context
DETAIL:  Call logout() first to change context
```

Permission denied:
```sql
SELECT login_as_anon();
ERROR:  permission denied
DETAIL:  Current user cannot switch to anonymous context
HINT:   Requires 'use_anon_context' permission
```

## Permissions Required

Caller must have either:
- 'use_anon_context' permission
- No active context

## Anonymous Policies

Default RLS policies for anonymous:

```sql
-- Public data access
CREATE POLICY anon_read ON items
    FOR SELECT
    USING (
        public = true
        AND current_user_context()->>'type' = 'anon'
    );

-- Rate limiting
CREATE POLICY anon_rate_limit ON api_requests
    FOR INSERT
    USING (
        current_user_context()->>'type' = 'anon'
        AND NOT EXISTS (
            SELECT 1 FROM api_requests
            WHERE client_ip = current_client_ip()
            AND created_at > now() - interval '1 minute'
            GROUP BY client_ip
            HAVING count(*) > 60
        )
    );
```

## Audit Trail

Creates audit entries:
```sql
-- Start anonymous context
INSERT INTO audit_log (event_type, event_data) VALUES (
    'anon_context_start',
    '{
        "previous_context": "api_key",
        "client_ip": "10.0.0.1"
    }'
);

-- End anonymous context
INSERT INTO audit_log (event_type, event_data) VALUES (
    'anon_context_end',
    '{
        "duration": "PT5M",
        "operations": ["SELECT"]
    }'
);
```

## See Also

- [logout()](logout.md) - Clear context
- [login_as_user()](login_as_user.md) - User context
- [current_user_context()](current_user_context.md) - Get context