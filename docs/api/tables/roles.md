# roles

Defines available roles for role-based access control.

## Table Definition

```sql
CREATE TABLE keyhippo_rbac.roles (
    role_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    tenant_id uuid,
    description text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT valid_role_name CHECK (name ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT unique_role_name UNIQUE (name, tenant_id)
);
```

## Indexes

```sql
-- Role lookup by name
CREATE UNIQUE INDEX idx_role_name 
ON roles(name) 
WHERE tenant_id IS NULL;

-- Tenant role lookup
CREATE UNIQUE INDEX idx_tenant_role_name 
ON roles(tenant_id, name) 
WHERE tenant_id IS NOT NULL;

-- Update timestamp maintenance
CREATE INDEX idx_role_updated 
ON roles(updated_at);
```

## Columns

| Name | Type | Description |
|------|------|-------------|
| role_id | uuid | Primary key |
| name | text | Role identifier (lowercase, underscores) |
| tenant_id | uuid | Optional tenant association |
| description | text | Role purpose and scope |
| metadata | jsonb | Additional role data |
| created_at | timestamptz | Creation timestamp |
| updated_at | timestamptz | Last modified timestamp |

## Default Roles

System creates these roles on initialization:
```sql
INSERT INTO roles (name, description) VALUES
('admin', 'Full system access'),
('user', 'Standard user access'),
('readonly', 'Read-only access to resources'),
('service', 'API service account access');
```

## Example Queries

List all roles:
```sql
SELECT name, description, 
       count(p.permission_id) as permission_count
FROM roles r
LEFT JOIN role_permissions p ON p.role_id = r.role_id
WHERE tenant_id IS NULL
GROUP BY r.role_id
ORDER BY name;
```

Find roles by permission:
```sql
SELECT r.name, r.description
FROM roles r
JOIN role_permissions rp ON rp.role_id = r.role_id
JOIN permissions p ON p.permission_id = rp.permission_id
WHERE p.name = 'create_api_key'
AND (r.tenant_id = current_tenant() OR r.tenant_id IS NULL);
```

Role hierarchy:
```sql
WITH RECURSIVE role_tree AS (
    SELECT role_id, name, 0 as level
    FROM roles
    WHERE name = 'admin'
    
    UNION ALL
    
    SELECT r.role_id, r.name, rt.level + 1
    FROM roles r
    JOIN role_inheritance ri ON ri.child_role_id = r.role_id
    JOIN role_tree rt ON rt.role_id = ri.parent_role_id
    WHERE rt.level < 5
)
SELECT LPAD('', level * 2, ' ') || name as role
FROM role_tree
ORDER BY level, name;
```

## Triggers

```sql
-- Maintain updated_at
CREATE TRIGGER update_role_timestamp
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Audit role changes
CREATE TRIGGER audit_role_changes
    AFTER INSERT OR UPDATE OR DELETE ON roles
    FOR EACH ROW
    EXECUTE FUNCTION audit_role_change();
```

## RLS Policies

```sql
-- Tenant isolation
CREATE POLICY tenant_roles ON roles
    FOR ALL
    USING (
        tenant_id IS NULL OR
        tenant_id = current_tenant()
    );

-- Role management permissions
CREATE POLICY manage_roles ON roles
    FOR ALL
    USING (
        has_permission('manage_roles')
    );
```

## See Also

- [role_permissions](role_permissions.md) - Role permission assignments
- [user_group_roles](user_group_roles.md) - User role assignments
- [create_role()](../functions/create_role.md) - Role creation
- [assign_role_to_user()](../functions/assign_role_to_user.md) - Role assignment