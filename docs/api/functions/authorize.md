# authorize

Checks if the current user or API key has a specific permission.

## Syntax

```sql
keyhippo.authorize(requested_permission keyhippo.app_permission)
RETURNS boolean
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| requested_permission | keyhippo.app_permission | The permission to check for |

## Returns

Returns `true` if the current context (user or API key) has the requested permission, `false` otherwise.

## Security

- SECURITY DEFINER function
- STABLE function (safe for use in RLS)
- Fixed search path for security
- Returns false on any error

## Performance

- P99 latency: 0.036ms
- Operations/sec: 27,778 (single core)
- Efficient permission lookup
- Suitable for RLS policies

## Example Usage

### In RLS Policy
```sql
CREATE POLICY "resource_access" ON resources
    FOR ALL
    USING (keyhippo.authorize('manage_resources'));
```

### Multiple Permissions
```sql
CREATE POLICY "admin_access" ON sensitive_data
    FOR ALL
    USING (
        keyhippo.authorize('admin_read')
        AND keyhippo.authorize('admin_write')
    );
```

### With User Check
```sql
CREATE POLICY "owner_or_admin" ON documents
    FOR ALL
    USING (
        owner_id = auth.uid()
        OR keyhippo.authorize('admin_access')
    );
```

## Implementation Examples

### Basic Permission Check
```sql
-- Check single permission
SELECT keyhippo.authorize('manage_users');

-- Check in procedure
CREATE OR REPLACE PROCEDURE update_user_data()
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT keyhippo.authorize('manage_users') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    -- Proceed with update
END;
$$;
```

### Complex Authorization
```sql
CREATE OR REPLACE FUNCTION can_access_resource(resource_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check basic access
    IF NOT keyhippo.authorize('read_resources') THEN
        RETURN false;
    END IF;

    -- Check specific permissions
    RETURN (
        -- Owner can always access
        EXISTS (
            SELECT 1 FROM resources 
            WHERE id = resource_id 
            AND owner_id = auth.uid()
        )
        OR
        -- Admins can access all resources
        keyhippo.authorize('admin_access')
        OR
        -- Users with explicit grant
        EXISTS (
            SELECT 1 FROM resource_grants
            WHERE resource_id = $1
            AND user_id = auth.uid()
        )
    );
END;
$$;
```

## Error Handling

1. **Invalid Permissions**
```sql
-- Returns false for non-existent permissions
SELECT keyhippo.authorize('invalid_permission');
```

2. **No Authentication**
```sql
-- Returns false when no user/key context
SELECT keyhippo.authorize('any_permission');
```

## Implementation Notes

1. **Permission Resolution**
   - Checks both user and API key permissions
   - Resolves through RBAC system
   - Handles API key scopes

2. **Performance Optimization**
   ```sql
   -- Cache frequent permission checks
   CREATE MATERIALIZED VIEW user_permissions AS
   SELECT 
       user_id,
       array_agg(DISTINCT p.name) as permissions
   FROM keyhippo_rbac.user_group_roles ugr
   JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
   JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
   GROUP BY user_id;
   ```

3. **Security Considerations**
   - Always use in RLS policies
   - Combine with row-level checks
   - Consider caching for performance

## Related Functions

- [current_user_context()](current_user_context.md)
- [verify_api_key()](verify_api_key.md)
- [is_authorized()](is_authorized.md)

## See Also

- [Permissions Table](../tables/permissions.md)
- [Role Permissions](../tables/role_permissions.md)
- [Security Best Practices](../security/rls_policies.md)