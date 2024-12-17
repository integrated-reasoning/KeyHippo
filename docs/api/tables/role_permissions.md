# role_permissions

Maps roles to their granted permissions with optional conditions.

## Table Definition

```sql
CREATE TABLE keyhippo_rbac.role_permissions (
    role_id uuid NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
    conditions jsonb,
    granted_at timestamptz NOT NULL DEFAULT now(),
    granted_by uuid NOT NULL,
    expires_at timestamptz,
    metadata jsonb,
    CONSTRAINT pk_role_permissions PRIMARY KEY (role_id, permission_id),
    CONSTRAINT valid_expiry CHECK (expires_at > granted_at)
);
```

## Indexes

```sql
-- Role permission lookup
CREATE INDEX idx_role_permissions_role 
ON role_permissions(role_id);

-- Permission assignment lookup
CREATE INDEX idx_role_permissions_permission 
ON role_permissions(permission_id);

-- Expiration checking
CREATE INDEX idx_role_permissions_expiry 
ON role_permissions(expires_at) 
WHERE expires_at IS NOT NULL;
```

## Columns

| Name | Type | Description |
|------|------|-------------|
| role_id | uuid | Role reference |
| permission_id | uuid | Permission reference |
| conditions | jsonb | Grant conditions |
| granted_at | timestamptz | Grant time |
| granted_by | uuid | Granting user |
| expires_at | timestamptz | Optional expiry |
| metadata | jsonb | Additional data |

## Example Queries

List role permissions:
```sql
SELECT 
    r.name as role,
    p.name as permission,
    rp.conditions,
    rp.expires_at
FROM role_permissions rp
JOIN roles r ON r.role_id = rp.role_id
JOIN permissions p ON p.permission_id = rp.permission_id
WHERE r.name = 'analyst'
ORDER BY p.name;
```

Check expired grants:
```sql
SELECT 
    r.name as role,
    p.name as permission,
    rp.expires_at
FROM role_permissions rp
JOIN roles r ON r.role_id = rp.role_id
JOIN permissions p ON p.permission_id = rp.permission_id
WHERE rp.expires_at < now() + interval '7 days'
ORDER BY rp.expires_at;
```

Permission inheritance tree:
```sql
WITH RECURSIVE permission_tree AS (
    -- Base permissions
    SELECT 
        r.role_id,
        r.name as role_name,
        p.name as permission_name,
        0 as depth
    FROM roles r
    JOIN role_permissions rp ON rp.role_id = r.role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    WHERE r.name = 'admin'
    
    UNION ALL
    
    -- Inherited permissions
    SELECT 
        r.role_id,
        r.name,
        p.name,
        pt.depth + 1
    FROM roles r
    JOIN role_inheritance ri ON ri.child_role_id = r.role_id
    JOIN role_permissions rp ON rp.role_id = ri.parent_role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    JOIN permission_tree pt ON pt.role_id = ri.parent_role_id
    WHERE pt.depth < 5
)
SELECT 
    LPAD('', depth * 2, ' ') || role_name as role,
    permission_name
FROM permission_tree
ORDER BY depth, role_name, permission_name;
```

## Condition Examples

Time-based access:
```json
{
    "time_window": {
        "start": "09:00",
        "end": "17:00",
        "timezone": "UTC",
        "weekdays": ["MON", "TUE", "WED", "THU", "FRI"]
    }
}
```

Resource limits:
```json
{
    "max_resources": 50,
    "resource_types": ["api_key"],
    "rate_limit": {
        "window": "1 hour",
        "max_requests": 100
    }
}
```

Network restrictions:
```json
{
    "ip_ranges": ["10.0.0.0/8"],
    "require_vpn": true,
    "countries": ["US", "CA"]
}
```

## Triggers

```sql
-- Validate conditions
CREATE TRIGGER validate_permission_conditions
    BEFORE INSERT OR UPDATE ON role_permissions
    FOR EACH ROW
    EXECUTE FUNCTION validate_permission_conditions();

-- Record grant in audit log
CREATE TRIGGER audit_permission_changes
    AFTER INSERT OR UPDATE OR DELETE ON role_permissions
    FOR EACH ROW
    EXECUTE FUNCTION audit_permission_change();
```

## RLS Policies

```sql
-- Role admins can manage permissions
CREATE POLICY manage_role_permissions ON role_permissions
    FOR ALL
    USING (
        has_permission('manage_roles')
    );

-- Users can view their permissions
CREATE POLICY view_role_permissions ON role_permissions
    FOR SELECT
    USING (
        role_id IN (
            SELECT r.role_id 
            FROM user_group_roles ugr
            JOIN roles r ON r.role_id = ugr.role_id
            WHERE ugr.user_id = current_user_id()
        )
    );
```

## See Also

- [roles](roles.md)
- [permissions](permissions.md)
- [assign_permission_to_role()](../functions/assign_permission_to_role.md)