# scopes

Defines available API key scopes and their permissions.

## Schema

```sql
CREATE TABLE keyhippo.scopes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    description text
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| name | text | Unique scope name |
| description | text | Optional description |

## Indexes

- Primary Key on `id`
- Unique index on `name`

## Security

- RLS enabled
- Requires manage_scopes permission
- Audit logged
- Referenced by API keys

## Example Usage

### Create Scope
```sql
INSERT INTO keyhippo.scopes (name, description)
VALUES (
    'analytics',
    'Access to analytics data'
);
```

### Scope with Permissions
```sql
DO $$
DECLARE
    scope_id uuid;
BEGIN
    -- Create scope
    INSERT INTO keyhippo.scopes (name, description)
    VALUES ('admin', 'Administrative access')
    RETURNING id INTO scope_id;
    
    -- Add permissions
    INSERT INTO keyhippo.scope_permissions (scope_id, permission_id)
    SELECT 
        scope_id,
        id
    FROM keyhippo_rbac.permissions
    WHERE name IN ('manage_users', 'manage_data');
END $$;
```

### Query Available Scopes
```sql
SELECT 
    s.name,
    s.description,
    array_agg(p.name) as permissions
FROM keyhippo.scopes s
LEFT JOIN keyhippo.scope_permissions sp ON s.id = sp.scope_id
LEFT JOIN keyhippo_rbac.permissions p ON sp.permission_id = p.id
GROUP BY s.id, s.name, s.description;
```

## Implementation Notes

1. **Access Control**
```sql
-- RLS policy
CREATE POLICY scopes_access_policy ON keyhippo.scopes
    FOR ALL
    TO authenticated
    USING (keyhippo.authorize('manage_scopes'))
    WITH CHECK (keyhippo.authorize('manage_scopes'));
```

2. **Audit Logging**
```sql
-- Via trigger
keyhippo_audit_scopes
```

3. **API Key Integration**
```sql
-- Referenced by
keyhippo.api_key_metadata.scope_id
```

## Related Tables

- [scope_permissions](scope_permissions.md)
- [api_key_metadata](api_key_metadata.md)
- [permissions](permissions.md)

## See Also

- [create_api_key()](../functions/create_api_key.md)
- [verify_api_key()](../functions/verify_api_key.md)
- [Security Policies](../security/rls_policies.md)