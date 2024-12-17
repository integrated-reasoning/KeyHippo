# current_user_context

Returns the current user context, handling both JWT and API key authentication methods.

## Syntax

```sql
keyhippo.current_user_context() 
RETURNS TABLE (
    user_id uuid,
    scope_id uuid,
    permissions text[]
)
```

## Returns

| Column | Type | Description |
|--------|------|-------------|
| user_id | uuid | The authenticated user's ID |
| scope_id | uuid | The scope ID if using API key authentication |
| permissions | text[] | Array of permission names granted to the user |

## Authentication Flow

1. Checks for API key in `x-api-key` header
2. If API key exists, validates it using `verify_api_key()`
3. If no API key or invalid, checks for JWT auth using `auth.uid()`
4. If no JWT, checks for impersonation session
5. Returns user context with appropriate permissions

## Security

- SECURITY DEFINER function
- Custom search path: `keyhippo_impersonation, keyhippo_rbac, keyhippo`
- Used by RLS policies and other security functions
- Safe for use in read-only transactions

## Example Usage

### Basic Usage

```sql
SELECT * FROM keyhippo.current_user_context();
```

### In RLS Policy

```sql
CREATE POLICY "user_access" ON "public"."resources"
    FOR ALL
    USING (
        user_id = (SELECT user_id FROM keyhippo.current_user_context())
    );
```

### Checking Permissions

```sql
CREATE POLICY "admin_access" ON "public"."sensitive_data"
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.current_user_context()
            WHERE 'admin_access' = ANY(permissions)
        )
    );
```

### With API Key Scopes

```sql
CREATE POLICY "scoped_access" ON "public"."api_resources"
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM keyhippo.current_user_context()
            WHERE scope_id = api_resources.scope_id
        )
    );
```

## Error Handling

- Returns NULL user_id if no valid authentication
- Returns empty permissions array if user has no permissions
- Safe to use in conditional statements
- No exceptions thrown

## Performance Considerations

- Caches API key validation results
- Minimizes permission lookups
- Safe for use in performance-critical paths
- Designed for frequent calls in RLS policies

## Related Functions

- [verify_api_key()](verify_api_key.md)
- [authorize()](authorize.md)
- [is_authorized()](is_authorized.md)

## Notes

- Core function for KeyHippo's security model
- Used extensively by internal functions
- Critical for RLS policy implementation
- Handles all authentication methods uniformly