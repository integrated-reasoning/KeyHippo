# current_user_context

Return the authentication context for the current database session.

## Synopsis

```sql
keyhippo.current_user_context() RETURNS jsonb
```

## Description

`current_user_context` returns cached authentication data from the current database session. The context is set by successful API key verification or user login.

## Return Value

Returns a JSONB object with this structure:
```json
{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "key_id": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "scope": "analytics",
    "tenant_id": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
    "type": "api_key",
    "roles": ["analyst", "reader"],
    "groups": ["analytics_team"],
    "metadata": {
        "key_description": "Analytics API",
        "authenticated_at": "2024-01-01T00:00:00Z"
    }
}
```

Returns NULL if no context is set.

## Examples

Check current context:
```sql
SELECT keyhippo.current_user_context();
```

Use in RLS policy:
```sql
CREATE POLICY tenant_access ON accounts
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
    );
```

Check role membership:
```sql
SELECT 
    CASE WHEN 'admin' = ANY(
        (current_user_context()->'roles')::text[]
    )
    THEN true
    ELSE false
    END as is_admin;
```

## Implementation Notes

1. Context is stored in GUC variable `keyhippo.current_context`
2. Set automatically by verify_api_key() and login functions
3. Cleared on transaction rollback
4. Cached for duration of transaction
5. JSON fields may be NULL if not applicable

## Context Types

The `type` field indicates the authentication method:

```sql
-- API key authentication
"type": "api_key"

-- Password authentication
"type": "password"

-- OAuth token
"type": "oauth"

-- Anonymous access
"type": "anon"
```

## Performance

Function performs minimal work:
1. Reads GUC variable
2. Parses JSON (already validated when set)
3. Returns cached result

No database queries are executed.

## Error Cases

Missing context:
```sql
SELECT current_user_context()->'user_id';
-- Returns NULL
```

Invalid JSON in context (should never happen):
```sql
ERROR:  invalid json in current_user_context
DETAIL:  Context was corrupted or incorrectly set
```

## See Also

- [verify_api_key()](verify_api_key.md) - Sets API key context
- [login_as_user()](login_as_user.md) - Sets user context
- [logout()](logout.md) - Clears context